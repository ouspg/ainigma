set local check_function_bodies = off;

drop function "private"."list_github_course_access_to_reconcile"();

create table "private"."course_repository_provisioning" (
  "course_id"             uuid                     not null,
  "profile_id"            uuid                     not null,
  "access_request_id"     uuid                     not null,
  "github_org_id"         bigint                   not null,
  "github_org_slug"       text                     not null,
  "repository_name"       text,
  "github_repository_id"  bigint,
  "github_repository_url" text,
  "state"                 text                     not null default 'queued'::text,
  "attempt_count"         integer                  not null default 0,
  "lease_token"           uuid,
  "lease_expires_at"      timestamp with time zone,
  "next_attempt_at"       timestamp with time zone not null default clock_timestamp(),
  "last_error"            text,
  "created_at"            timestamp with time zone not null default clock_timestamp(),
  "updated_at"            timestamp with time zone not null default clock_timestamp(),
  constraint "course_repository_provisioning_attempt_check" check ((attempt_count >= 0)),
  constraint "course_repository_provisioning_error_check"
    check (((last_error IS NULL) OR ((last_error = btrim(last_error)) AND ((char_length(last_error) >= 1) AND (char_length(last_error) <= 1000))))),
  constraint "course_repository_provisioning_lease_check" check ((((state = 'provisioning'::text) AND (lease_token IS NOT NULL) AND (lease_expires_at IS
    NOT NULL)) OR ((state <> 'provisioning'::text) AND (lease_token IS NULL) AND (lease_expires_at IS NULL)))),
  constraint "course_repository_provisioning_name_check"
    check (((repository_name IS NULL) OR ((repository_name = btrim(repository_name)) AND ((char_length(repository_name) >= 1) AND (char_length(repository_name) <= 100))))),
  constraint "course_repository_provisioning_org_id_check" check ((github_org_id > 0)),
  constraint "course_repository_provisioning_org_slug_check"
    check (((github_org_slug = btrim(github_org_slug)) AND ((char_length(github_org_slug) >= 1) AND (char_length(github_org_slug) <= 255)))),
  constraint "course_repository_provisioning_pkey" primary key (course_id, profile_id),
  constraint "course_repository_provisioning_ready_shape_check" check ((((state = 'ready'::text) AND (repository_name IS NOT NULL) AND (github_repository_id IS
    NOT NULL) AND (github_repository_url IS NOT NULL)) OR (state <> 'ready'::text))),
  constraint "course_repository_provisioning_repository_id_check" check (((github_repository_id IS NULL) OR (github_repository_id > 0))),
  constraint "course_repository_provisioning_state_check" check ((state = ANY (ARRAY['queued'::text, 'provisioning'::text, 'ready'::text, 'failed'::text]))),
  constraint "course_repository_provisioning_url_check"
    check
    (((github_repository_url IS NULL) OR ((github_repository_url = btrim(github_repository_url)) AND ((char_length(github_repository_url) >= 1) AND
    (char_length(github_repository_url) <= 2048)))))
);

alter table "private"."course_repository_provisioning"
  enable row level security;

alter table "private"."course_repository_provisioning"
  force row level security;

alter table "private"."github_course_access"
  add column "github_username" text;

alter table "private"."github_course_access"
  add column "invitation_method" text not null default 'email'::text;

alter table "private"."github_course_access"
  add column "invitation_target" text;

create or replace function private.claim_course_repository_provisioning (
  p_limit      integer default 25,
  p_course_id  uuid    default null::uuid,
  p_profile_id uuid    default null::uuid
)
  returns table (
    course_id             uuid,
    profile_id            uuid,
    access_request_id     uuid,
    offering_key          text,
    github_org_id         bigint,
    github_org_slug       text,
    repository_name       text,
    github_repository_id  bigint,
    github_repository_url text,
    github_username       text,
    github_user_id        text,
    lease_token           uuid,
    attempt_count         integer
  )
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'invalid_repository_claim_limit';
  end if;

  return query
  with candidates as (
    select
      repository.course_id,
      repository.profile_id,
      repository.access_request_id,
      course.offering_key,
      repository.github_org_id,
      repository.github_org_slug,
      repository.github_repository_id,
      repository.github_repository_url,
      access_row.github_user_id,
      username.normalized_value as github_username,
      case
        when username.normalized_value is null then null
        when char_length('submissions-' || course.offering_key || '-' || username.normalized_value) <= 100
          then 'submissions-' || course.offering_key || '-' || username.normalized_value
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || username.normalized_value), 8) || '-' ||
          left(username.normalized_value, 20)
      end as generated_repository_name
    from private.course_repository_provisioning as repository
    join private.github_course_access as access_row
      on access_row.course_id = repository.course_id
     and access_row.profile_id = repository.profile_id
    join private.course_access_requests as request_row
      on request_row.id = repository.access_request_id
     and request_row.course_id = repository.course_id
     and request_row.requester_profile_id = repository.profile_id
    join public.course_memberships as membership
      on membership.course_id = repository.course_id
     and membership.profile_id = repository.profile_id
     and membership.created_from_access_request_id = repository.access_request_id
     and membership.status = 'active'
    join public.courses as course on course.id = repository.course_id
    left join lateral (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = repository.profile_id
        and identifier.kind = 'github_username'
        and identifier.issuer = 'github.com'
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ) as username on true
    where request_row.status = 'approved'
      and access_row.state = 'active'
      and (p_course_id is null or repository.course_id = p_course_id)
      and (p_profile_id is null or repository.profile_id = p_profile_id)
      and (
        repository.state = 'queued'
        or (repository.state = 'failed' and repository.next_attempt_at <= clock_timestamp())
        or (repository.state = 'provisioning' and repository.lease_expires_at <= clock_timestamp())
      )
    order by repository.updated_at, repository.created_at
    limit p_limit
    for update of repository skip locked
  ), claimed as (
    update private.course_repository_provisioning as repository
    set state = 'provisioning',
        lease_token = gen_random_uuid(),
        lease_expires_at = clock_timestamp() + interval '5 minutes',
        attempt_count = repository.attempt_count + 1,
        repository_name = candidates.generated_repository_name,
        last_error = null,
        updated_at = clock_timestamp()
    from candidates
    where repository.course_id = candidates.course_id
      and repository.profile_id = candidates.profile_id
    returning repository.*
  )
  select
    claimed.course_id,
    claimed.profile_id,
    claimed.access_request_id,
    course.offering_key,
    claimed.github_org_id,
    claimed.github_org_slug,
    claimed.repository_name,
    claimed.github_repository_id,
    claimed.github_repository_url,
    username.normalized_value,
    access_row.github_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.github_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = claimed.profile_id
      and identifier.kind = 'github_username'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as username on true;
end
$function$;

alter function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) owner to "ainigma_function_owner";

create or replace function private.complete_course_repository_provisioning (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_lease_token            uuid,
  p_github_repository_id   bigint,
  p_github_repository_name text,
  p_github_repository_url  text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_repository private.course_repository_provisioning%rowtype;
begin
  if p_github_repository_id is null
    or p_github_repository_id <= 0
    or p_github_repository_name is null
    or p_github_repository_name <> btrim(p_github_repository_name)
    or char_length(p_github_repository_name) not between 1 and 100
    or p_github_repository_url is null
    or p_github_repository_url <> btrim(p_github_repository_url)
    or char_length(p_github_repository_url) not between 1 and 2048
  then
    raise exception using errcode = '22023', message = 'invalid_github_repository';
  end if;

  select repository.*
  into v_repository
  from private.course_repository_provisioning as repository
  where repository.course_id = p_course_id
    and repository.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'repository_provisioning_not_started';
  end if;

  if v_repository.state = 'ready' then
    if v_repository.github_repository_id = p_github_repository_id
      and v_repository.repository_name = p_github_repository_name
      and v_repository.github_repository_url = p_github_repository_url
    then
      return;
    end if;
    raise exception using errcode = '55000', message = 'repository_already_bound';
  end if;

  if v_repository.state <> 'provisioning'
    or v_repository.lease_token is distinct from p_lease_token
  then
    raise exception using errcode = '55000', message = 'repository_lease_invalid';
  end if;

  if v_repository.repository_name is distinct from p_github_repository_name then
    raise exception using errcode = '42501', message = 'repository_name_mismatch';
  end if;

  update private.course_repository_provisioning
  set state = 'ready',
      github_repository_id = p_github_repository_id,
      github_repository_url = p_github_repository_url,
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = clock_timestamp(),
      last_error = null,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, bigint, text, text) owner to "ainigma_function_owner";

create or replace function private.confirm_github_course_access (
  p_course_id       uuid,
  p_profile_id      uuid,
  p_github_org_id   bigint,
  p_github_org_slug text,
  p_github_user_id  text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_github_org_id bigint;
  v_expected_github_org_slug text;
  v_github_username text;
begin
  select access_row.* into v_access
  from private.github_course_access as access_row
  where access_row.course_id = p_course_id and access_row.profile_id = p_profile_id
  for update;

  if not found then raise exception using errcode = '23503', message = 'github_access_not_started'; end if;

  select request_row.* into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id and request_row.status = 'approved';
  if not found then raise exception using errcode = '42501', message = 'course_access_not_approved'; end if;

  select organization.github_org_id, organization.github_org_slug
  into v_expected_github_org_id, v_expected_github_org_slug
  from public.courses as course
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found or p_github_org_id is distinct from v_expected_github_org_id then
    raise exception using errcode = '42501', message = 'github_organization_mismatch';
  end if;

  if not exists (
    select 1 from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'github_user_id'
      and identifier.issuer = 'github.com'
      and identifier.normalized_value = p_github_user_id
      and identifier.revoked_at is null
  ) then
    raise exception using errcode = '42501', message = 'github_identity_mismatch';
  end if;

  select identifier.normalized_value
  into v_github_username
  from private.profile_identifiers as identifier
  where identifier.profile_id = p_profile_id
    and identifier.kind = 'github_username'
    and identifier.issuer = 'github.com'
    and identifier.revoked_at is null
  order by identifier.last_verified_at desc
  limit 1;

  update private.github_course_access
  set github_org_id = p_github_org_id,
      github_org_slug = v_expected_github_org_slug,
      github_user_id = p_github_user_id,
      github_username = v_github_username,
      state = 'active',
      accepted_at = coalesce(accepted_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null
  where course_id = p_course_id and profile_id = p_profile_id;

  insert into public.course_memberships (
    course_id, profile_id, role, status, created_from_access_request_id
  ) values (
    p_course_id, p_profile_id, 'learner', 'active', v_request.id
  )
  on conflict (course_id, profile_id) do nothing;

  insert into private.course_membership_events (
    course_id, profile_id, event_kind, new_role, new_status, actor_profile_id, reason
  )
  select p_course_id, p_profile_id, 'created', 'learner', 'active', null,
    'GitHub course organization membership confirmed'
  where not exists (
    select 1 from private.course_membership_events as event_row
    where event_row.course_id = p_course_id
      and event_row.profile_id = p_profile_id
      and event_row.event_kind = 'created'
      and event_row.new_role = 'learner'
      and event_row.new_status = 'active'
  );

  insert into private.course_repository_provisioning (
    course_id, profile_id, access_request_id, github_org_id, github_org_slug
  ) values (
    p_course_id, p_profile_id, v_request.id,
    v_expected_github_org_id, v_expected_github_org_slug
  )
  on conflict (course_id, profile_id) do nothing;
end
$function$;

create or replace function private.fail_course_repository_provisioning (
  p_course_id           uuid,
  p_profile_id          uuid,
  p_lease_token         uuid,
  p_error_code          text,
  p_retry_after_seconds integer default 60
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_state text;
  v_lease_token uuid;
begin
  if p_error_code is null
    or p_error_code <> btrim(p_error_code)
    or char_length(p_error_code) not between 1 and 255
    or p_retry_after_seconds is null
    or p_retry_after_seconds < 1
    or p_retry_after_seconds > 86400
  then
    raise exception using errcode = '22023', message = 'invalid_repository_failure';
  end if;

  select repository.state, repository.lease_token
  into v_state, v_lease_token
  from private.course_repository_provisioning as repository
  where repository.course_id = p_course_id
    and repository.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'repository_provisioning_not_started';
  end if;

  if v_state = 'failed' then
    return;
  end if;

  if v_state <> 'provisioning' or v_lease_token is distinct from p_lease_token then
    raise exception using errcode = '55000', message = 'repository_lease_invalid';
  end if;

  update private.course_repository_provisioning
  set state = 'failed',
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = clock_timestamp() + make_interval(secs => p_retry_after_seconds),
      last_error = p_error_code,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."fail_course_repository_provisioning"(uuid, uuid, uuid, text, integer) owner to "ainigma_function_owner";

create or replace function private.list_github_course_access_to_reconcile()
  returns table (
    course_id                uuid,
    profile_id               uuid,
    access_request_id        uuid,
    offering_key             text,
    expected_github_org_id   bigint,
    expected_github_org_slug text,
    github_user_id           text,
    github_username          text,
    github_email             text,
    invitation_method        text,
    invitation_target        text,
    state                    text
  )
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select
    access_row.course_id,
    access_row.profile_id,
    access_row.access_request_id,
    course.offering_key,
    organization.github_org_id,
    organization.github_org_slug,
    access_row.github_user_id,
    username.normalized_value,
    email.normalized_value,
    access_row.invitation_method,
    access_row.invitation_target,
    access_row.state
  from private.github_course_access as access_row
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
  join public.courses as course on course.id = access_row.course_id
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = access_row.profile_id
      and identifier.kind = 'github_username'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as username on true
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = access_row.profile_id
      and identifier.kind = 'email'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as email on true
  where request_row.status = 'approved'
    and access_row.state <> 'revoked';
$function$;

alter function "private"."list_github_course_access_to_reconcile"() owner to "ainigma_function_owner";

create or replace function private.record_github_course_access_invitation (
  p_course_id         uuid,
  p_profile_id        uuid,
  p_invitation_method text,
  p_invitation_target text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.github_course_access%rowtype;
  v_expected_target text;
  v_expected_github_org_id bigint;
  v_expected_github_org_slug text;
begin
  if p_invitation_method not in ('email', 'username')
    or p_invitation_target is null
    or p_invitation_target <> btrim(p_invitation_target)
    or char_length(p_invitation_target) not between 1 and 512
  then
    raise exception using errcode = '22023', message = 'invalid_github_invitation_target';
  end if;

  select access_row.*
  into v_access
  from private.github_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'github_access_not_started';
  end if;

  select identifier.normalized_value
  into v_expected_target
  from private.profile_identifiers as identifier
  where identifier.profile_id = p_profile_id
    and identifier.kind = case when p_invitation_method = 'email' then 'email' else 'github_username' end
    and identifier.issuer = 'github.com'
    and identifier.revoked_at is null
  order by identifier.last_verified_at desc
  limit 1;

  if v_expected_target is null or v_expected_target <> p_invitation_target then
    raise exception using errcode = '42501', message = 'github_invitation_identity_mismatch';
  end if;

  select organization.github_org_id, organization.github_org_slug
  into v_expected_github_org_id, v_expected_github_org_slug
  from public.courses as course
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'github_organization_not_configured';
  end if;

  if v_access.state = 'active' then
    return;
  end if;

  update private.github_course_access
  set github_org_id = v_expected_github_org_id,
      github_org_slug = v_expected_github_org_slug,
      invitation_method = p_invitation_method,
      invitation_target = p_invitation_target,
      state = 'invitation_pending',
      invited_at = coalesce(invited_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_github_course_access_invitation"(uuid, uuid, text, text) owner to "ainigma_function_owner";

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_access_fkey" foreign key (course_id, profile_id) references private.github_course_access(course_id, profile_id) on delete restrict;

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_request_fkey" foreign key (access_request_id, course_id, profile_id)
    references private.course_access_requests(id, course_id, requester_profile_id) on delete restrict;

alter table "private"."github_course_access"
  add constraint "github_course_access_invitation_method_check" check ((invitation_method = ANY (ARRAY['email'::text, 'username'::text])));

alter table "private"."github_course_access"
  add constraint "github_course_access_invitation_target_check"
    check
    (((invitation_target IS NULL) OR ((invitation_target = btrim(invitation_target)) AND ((char_length(invitation_target) >= 1) AND (char_length(invitation_target) <= 512)))));

alter table "private"."github_course_access"
  add constraint "github_course_access_username_check"
    check (((github_username IS NULL) OR ((github_username = btrim(github_username)) AND (github_username ~ '^[A-Za-z0-9-]+$'::text))));

create index course_repository_provisioning_claim_idx on private.course_repository_provisioning using btree (state, next_attempt_at, lease_expires_at, updated_at);

create unique index course_repository_provisioning_org_name_uidx on private.course_repository_provisioning using btree (github_org_id, repository_name)
  where (repository_name is not null);

create unique index course_repository_provisioning_repository_id_uidx on private.course_repository_provisioning using btree (github_repository_id)
  where (github_repository_id is not null);

create trigger course_repository_provisioning_set_updated_at
  before update on private.course_repository_provisioning
  for each row
  execute function private.set_updated_at();

create policy "course_repository_provisioning_function_access" on "private"."course_repository_provisioning"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

comment on column "private"."course_repository_provisioning"."github_repository_id" is 'Stable GitHub repository ID; used instead of the mutable repository name for reconciliation.';

comment on column "private"."course_repository_provisioning"."repository_name" is 'Deterministic offering-specific GitHub repository name, normally submissions-<offering_key>-<username>.';

comment on table "private"."course_repository_provisioning" is 'Durable idempotent outbox for one GitHub submissions repository per offering and profile.';

revoke all on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) from public;

grant execute on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) to "ainigma_maintenance";

revoke all on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, bigint, text, text) from public;

grant execute on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, bigint, text, text) to "ainigma_maintenance";

revoke all on function "private"."fail_course_repository_provisioning"(uuid, uuid, uuid, text, integer) from public;

grant execute on function "private"."fail_course_repository_provisioning"(uuid, uuid, uuid, text, integer) to "ainigma_maintenance";

revoke all on function "private"."list_github_course_access_to_reconcile"() from public;

grant execute on function "private"."list_github_course_access_to_reconcile"() to "ainigma_maintenance";

revoke all on function "private"."record_github_course_access_invitation"(uuid, uuid, text, text) from public;

grant execute on function "private"."record_github_course_access_invitation"(uuid, uuid, text, text) to "ainigma_maintenance";

grant insert, select, update on table "private"."course_repository_provisioning" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_repository_provisioning" to "postgres";
