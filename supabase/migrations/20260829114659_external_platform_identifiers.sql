set local check_function_bodies = off;

drop index "private"."course_repository_provisioning_org_name_uidx";

drop index "private"."course_repository_provisioning_repository_id_uidx";

alter table "private"."course_definition_releases"
  drop constraint "course_definition_releases_github_organization_fkey";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_access_identity_fkey";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_org_id_check";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_org_slug_check";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_ready_shape_check";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_repository_id_check";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_url_check";

alter table "private"."course_roster_allowlist"
  drop constraint "course_roster_allowlist_kind_check";

alter table "private"."github_course_access"
  drop constraint "github_course_access_course_id_fkey";

alter table "private"."github_course_access"
  drop constraint "github_course_access_profile_id_fkey";

alter table "private"."github_course_access"
  drop constraint "github_course_access_request_course_profile_fk";

alter table "private"."profile_identifiers"
  drop constraint "profile_identifiers_kind_check";

alter table "public"."courses"
  drop constraint "courses_course_definition_github_organization_fkey";

drop function "private"."claim_course_repository_provisioning"(integer, uuid, uuid);

drop function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, bigint, text, text);

drop function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, bigint, text, text);

drop function "private"."list_github_course_access_to_reconcile"();

drop function "private"."record_github_course_access_check_failure"(uuid, uuid, text);

drop function "private"."record_github_course_access_invitation"(uuid, uuid, text, text, bigint);

drop function "private"."record_github_course_access_membership_absence"(uuid, uuid);

drop function "private"."record_github_course_access_status"(uuid, uuid, text, text);

drop function "public"."list_course_access_requests"(text, text, text);

drop function "public"."list_my_course_access_requests"();

alter table "private"."course_repository_provisioning"
  drop column "github_org_id";

alter table "private"."course_repository_provisioning"
  drop column "github_org_slug";

alter table "private"."course_repository_provisioning"
  drop column "github_repository_id";

alter table "private"."course_repository_provisioning"
  drop column "github_repository_url";

drop table "private"."course_definition_github_organizations";

drop table "private"."github_course_access";

create table "private"."course_definition_external_groups" (
  "course_definition_key" text                     not null,
  "provider_kind"         text                     not null default 'github'::text,
  "provider_issuer"       text                     not null default 'github.com'::text,
  "external_group_id"     text                     not null,
  "external_group_handle" text                     not null,
  "created_at"            timestamp with time zone not null default clock_timestamp(),
  constraint "course_definition_external_groups_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "course_definition_external_groups_group_id_check"
    check (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255)))),
  constraint "course_definition_external_groups_org_slug_check"
    check (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255)))),
  constraint "course_definition_external_groups_pkey" primary key (course_definition_key),
  constraint "course_definition_external_groups_provider_issuer_check"
    check
    (((provider_issuer = btrim(provider_issuer)) AND ((char_length(provider_issuer) >= 1) AND (char_length(provider_issuer) <= 255)) AND (provider_issuer !~ '[[:space:]]'::text))),
  constraint "course_definition_external_groups_provider_kind_check" check (((provider_kind = btrim(provider_kind)) AND (provider_kind ~ '^[a-z][a-z0-9_]{0,63}$'::text)))
);

create table "private"."external_course_access" (
  "course_id"                       uuid                     not null,
  "profile_id"                      uuid                     not null,
  "access_request_id"               uuid                     not null,
  "external_group_id"               text,
  "external_group_handle"           text,
  "external_user_id"                text                     not null,
  "external_user_handle"            text,
  "external_invitation_id"          text,
  "invitation_method"               text                     not null default 'email'::text,
  "invitation_target"               text,
  "state"                           text                     not null default 'not_started'::text,
  "invited_at"                      timestamp with time zone,
  "accepted_at"                     timestamp with time zone,
  "last_checked_at"                 timestamp with time zone,
  "failure_code"                    text,
  "consecutive_membership_absences" integer                  not null default 0,
  constraint "external_course_access_failure_check"
    check (((failure_code IS NULL) OR ((failure_code = btrim(failure_code)) AND ((char_length(failure_code) >= 1) AND (char_length(failure_code) <= 255))))),
  constraint "external_course_access_group_handle_check"
    check
    (((external_group_handle IS NULL) OR ((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND
    (char_length(external_group_handle) <= 255))))),
  constraint "external_course_access_group_shape_check"
    check ((((state = 'not_started'::text) AND (external_group_id IS NULL) AND (external_group_handle IS NULL)) OR ((state <> 'not_started'::text) AND (external_group_id IS
    NOT NULL) AND (external_group_handle IS NOT NULL)))),
  constraint "external_course_access_invitation_id_check"
    check
    (((external_invitation_id IS NULL) OR ((external_invitation_id = btrim(external_invitation_id)) AND ((char_length(external_invitation_id) >= 1) AND
    (char_length(external_invitation_id) <= 255))))),
  constraint "external_course_access_invitation_method_check" check ((invitation_method = ANY (ARRAY['email'::text, 'external_user_id'::text]))),
  constraint "external_course_access_invitation_target_check"
    check
    (((invitation_target IS NULL) OR ((invitation_target = btrim(invitation_target)) AND ((char_length(invitation_target) >= 1) AND (char_length(invitation_target) <= 512))))),
  constraint "external_course_access_membership_absences_check" check ((consecutive_membership_absences >= 0)),
  constraint "external_course_access_pkey" primary key (course_id, profile_id),
  constraint "external_course_access_repository_identity_unique" unique (course_id, profile_id, access_request_id, external_group_id, external_group_handle),
  constraint "external_course_access_state_check"
    check ((state = ANY (ARRAY['not_started'::text, 'invitation_pending'::text, 'sso_required'::text, 'active'::text, 'failed'::text, 'revoked'::text]))),
  constraint "external_course_access_user_handle_check"
    check
    (((external_user_handle IS NULL) OR ((external_user_handle = btrim(external_user_handle)) AND ((char_length(external_user_handle) >= 1) AND (char_length(external_user_handle)
    <= 255)) AND (external_user_handle !~ '[[:space:]]'::text)))),
  constraint "external_course_access_user_id_check"
    check (((external_user_id = btrim(external_user_id)) AND ((char_length(external_user_id) >= 1) AND (char_length(external_user_id) <= 255))))
);

alter table "private"."external_course_access"
  enable row level security;

alter table "private"."external_course_access"
  force row level security;

alter table "private"."course_repository_provisioning"
  add column "external_group_id" text not null;

alter table "private"."course_repository_provisioning"
  add column "external_group_handle" text not null;

alter table "private"."course_repository_provisioning"
  add column "external_repository_id" text;

alter table "private"."course_repository_provisioning"
  add column "external_repository_url" text;

create or replace function private.claim_course_repository_provisioning (
  p_limit      integer default 25,
  p_course_id  uuid    default null::uuid,
  p_profile_id uuid    default null::uuid
)
  returns table (
    course_id               uuid,
    profile_id              uuid,
    access_request_id       uuid,
    offering_key            text,
    provider_kind           text,
    external_group_id       text,
    external_group_handle   text,
    repository_name         text,
    external_repository_id  text,
    external_repository_url text,
    external_user_handle    text,
    external_user_id        text,
    lease_token             uuid,
    attempt_count           integer
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
      organization.provider_kind,
      repository.external_group_id,
      repository.external_group_handle,
      repository.external_repository_id,
      repository.external_repository_url,
      access_row.external_user_id,
      access_row.external_user_handle,
      case
        when access_row.external_user_handle is null then null
        when char_length('submissions-' || course.offering_key || '-' || access_row.external_user_handle) <= 100
          then 'submissions-' || course.offering_key || '-' || access_row.external_user_handle
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || access_row.external_user_handle), 8) || '-' ||
          left(access_row.external_user_handle, 20)
      end as generated_repository_name
    from private.course_repository_provisioning as repository
    join private.external_course_access as access_row
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
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = course.course_definition_key
    where request_row.status = 'approved'
      and access_row.state = 'active'
      and access_row.external_user_handle is not null
      and access_row.failure_code is null
      and access_row.last_checked_at >= clock_timestamp() - interval '5 minutes'
      and (p_course_id is null or repository.course_id = p_course_id)
      and (p_profile_id is null or repository.profile_id = p_profile_id)
      and (
        repository.state = 'queued'
        or (repository.state = 'retry_wait' and repository.next_attempt_at <= clock_timestamp())
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
        repository_name = coalesce(repository.repository_name, candidates.generated_repository_name),
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
    organization.provider_kind,
    claimed.external_group_id,
    claimed.external_group_handle,
    claimed.repository_name,
    claimed.external_repository_id,
    claimed.external_repository_url,
    access_row.external_user_handle,
    access_row.external_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  join private.external_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
  ;
end
$function$;

alter function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) owner to "ainigma_function_owner";

create or replace function private.complete_course_repository_provisioning (
  p_course_id               uuid,
  p_profile_id              uuid,
  p_lease_token             uuid,
  p_external_repository_id  text,
  p_repository_name         text,
  p_external_repository_url text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_repository private.course_repository_provisioning%rowtype;
begin
  if p_external_repository_id is null
    or p_external_repository_id <> btrim(p_external_repository_id)
    or char_length(p_external_repository_id) not between 1 and 255
    or p_repository_name is null
    or p_repository_name <> btrim(p_repository_name)
    or char_length(p_repository_name) not between 1 and 100
    or p_external_repository_url is null
    or p_external_repository_url <> btrim(p_external_repository_url)
    or char_length(p_external_repository_url) not between 1 and 2048
  then
    raise exception using errcode = '22023', message = 'invalid_external_repository';
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
    if v_repository.external_repository_id = p_external_repository_id
      and v_repository.repository_name = p_repository_name
      and v_repository.external_repository_url = p_external_repository_url
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

  if v_repository.repository_name is distinct from p_repository_name then
    raise exception using errcode = '42501', message = 'repository_name_mismatch';
  end if;

  update private.course_repository_provisioning
  set state = 'ready',
      external_repository_id = p_external_repository_id,
      external_repository_url = p_external_repository_url,
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = null,
      last_error = null,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) owner to "ainigma_function_owner";

create or replace function private.confirm_external_course_access (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_external_group_id      text,
  p_external_group_handle  text,
  p_external_invitation_id text,
  p_external_user_id       text,
  p_external_user_handle   text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_provider_issuer text;
begin
  if p_external_group_id is null
    or p_external_group_id <> btrim(p_external_group_id)
    or char_length(p_external_group_id) not between 1 and 255
    or p_external_group_handle is null
    or p_external_group_handle <> btrim(p_external_group_handle)
    or char_length(p_external_group_handle) not between 1 and 255
    or p_external_invitation_id is null
    or p_external_invitation_id <> btrim(p_external_invitation_id)
    or char_length(p_external_invitation_id) not between 1 and 255
    or p_external_user_id is null
    or p_external_user_id <> btrim(p_external_user_id)
    or char_length(p_external_user_id) not between 1 and 255
    or p_external_user_handle is null
    or p_external_user_handle <> btrim(p_external_user_handle)
    or char_length(p_external_user_handle) not between 1 and 255
    or p_external_user_handle ~ '[[:space:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_external_membership_identity';
  end if;

  select organization.external_group_id,
         organization.external_group_handle,
         organization.provider_issuer
  into v_expected_external_group_id,
       v_expected_external_group_handle,
       v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
  for update of course;

  if not found then
    raise exception using errcode = '55000', message = 'course_offering_not_reconcilable';
  end if;

  select access_row.* into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id and access_row.profile_id = p_profile_id
  for update;

  if not found then raise exception using errcode = '23503', message = 'external_access_not_started'; end if;

  select request_row.* into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id and request_row.status = 'approved';
  if not found then raise exception using errcode = '42501', message = 'course_access_not_approved'; end if;

  if p_external_group_id is distinct from v_expected_external_group_id
    or p_external_group_handle is distinct from v_expected_external_group_handle
  then
    raise exception using errcode = '42501', message = 'external_group_mismatch';
  end if;

  if v_access.external_invitation_id is distinct from p_external_invitation_id then
    raise exception using errcode = '42501', message = 'external_invitation_mismatch';
  end if;

  if not exists (
    select 1 from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = v_provider_issuer
      and identifier.normalized_value = p_external_user_id
      and identifier.revoked_at is null
  ) then
    raise exception using errcode = '42501', message = 'external_identity_mismatch';
  end if;

  update private.external_course_access
  set external_group_id = p_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      external_user_id = p_external_user_id,
      external_user_handle = p_external_user_handle,
      state = 'active',
      accepted_at = coalesce(accepted_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null,
      consecutive_membership_absences = 0
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
    'GitHub organization invitation and membership confirmed'
  where not exists (
    select 1 from private.course_membership_events as event_row
    where event_row.course_id = p_course_id
      and event_row.profile_id = p_profile_id
      and event_row.event_kind = 'created'
      and event_row.new_role = 'learner'
      and event_row.new_status = 'active'
  );

end
$function$;

alter function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) owner to "ainigma_function_owner";

create or replace function private.list_external_course_access_to_reconcile()
  returns table (
    course_id                      uuid,
    profile_id                     uuid,
    access_request_id              uuid,
    offering_key                   text,
    provider_kind                  text,
    provider_issuer                text,
    expected_external_group_id     text,
    expected_external_group_handle text,
    external_user_id               text,
    external_user_handle           text,
    external_invitation_id         text,
    external_email                 text,
    invitation_method              text,
    invitation_target              text,
    state                          text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select access_row.course_id,
     access_row.profile_id,
     access_row.access_request_id,
     course.offering_key,
     organization.provider_kind,
     organization.provider_issuer,
     organization.external_group_id,
     organization.external_group_handle,
     access_row.external_user_id,
     access_row.external_user_handle,
     access_row.external_invitation_id,
     email.normalized_value,
     access_row.invitation_method,
     access_row.invitation_target,
     access_row.state
    from ((((private.external_course_access access_row
      JOIN private.course_access_requests request_row
        on (((request_row.id = access_row.access_request_id) AND (request_row.course_id = access_row.course_id) AND (request_row.requester_profile_id = access_row.profile_id))))
      JOIN public.courses course on ((course.id = access_row.course_id)))
      JOIN private.course_definition_external_groups organization on ((organization.course_definition_key = course.course_definition_key)))
      LEFT JOIN LATERAL ( select identifier.normalized_value
            from private.profile_identifiers identifier
           where
             ((identifier.profile_id = access_row.profile_id) AND (identifier.kind = 'email'::text) AND (identifier.issuer = organization.provider_issuer) AND
             (identifier.revoked_at is null))
           ORDER by identifier.last_verified_at desc
          limit 1) email on (true))
   where ((request_row.status = 'approved'::text) AND (course.status = 'published'::text) AND (access_row.state <> 'revoked'::text));
end;

alter function "private"."list_external_course_access_to_reconcile"() owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_check_failure (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_failure_code text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_failure_code text := nullif(btrim(p_failure_code), '');
begin
  if v_failure_code is null or char_length(v_failure_code) > 255 then
    raise exception using errcode = '22023', message = 'invalid_external_access_failure_code';
  end if;

  update private.external_course_access as access_row
  set last_checked_at = clock_timestamp(),
      failure_code = v_failure_code
  from private.course_access_requests as request_row,
       public.courses as course
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
    and request_row.id = access_row.access_request_id
    and request_row.course_id = access_row.course_id
    and request_row.requester_profile_id = access_row.profile_id
    and request_row.status = 'approved'
    and course.id = access_row.course_id
    and course.status = 'published'
    and access_row.state <> 'revoked';

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_reconcilable';
  end if;
end
$function$;

alter function "private"."record_external_course_access_check_failure"(uuid, uuid, text) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_invitation (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_invitation_method      text,
  p_invitation_target      text,
  p_external_invitation_id text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
begin
  if p_invitation_method not in ('email', 'external_user_id')
    or p_invitation_target is null
    or p_invitation_target <> btrim(p_invitation_target)
    or char_length(p_invitation_target) not between 1 and 512
    or p_external_invitation_id is null
    or p_external_invitation_id <> btrim(p_external_invitation_id)
    or char_length(p_external_invitation_id) not between 1 and 255
  then
    raise exception using errcode = '22023', message = 'invalid_external_invitation_target';
  end if;

  select access_row.*
  into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_started';
  end if;

  perform 1
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id
    and request_row.course_id = p_course_id
    and request_row.requester_profile_id = p_profile_id
    and request_row.status = 'approved';

  if not found then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  if p_invitation_method = 'email' then
    select identifier.normalized_value
    into v_expected_target
    from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'email'
      and identifier.issuer = (
        select organization.provider_issuer
        from public.courses as course
        join private.course_definition_external_groups as organization
          on organization.course_definition_key = course.course_definition_key
        where course.id = p_course_id
      )
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;
  else
    v_expected_target := v_access.external_user_id;
  end if;

  if v_expected_target is null or v_expected_target <> p_invitation_target then
    raise exception using errcode = '42501', message = 'external_invitation_identity_mismatch';
  end if;

  select organization.external_group_id, organization.external_group_handle
  into v_expected_external_group_id, v_expected_external_group_handle
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'external_group_not_configured';
  end if;

  if v_access.state = 'active' then
    return;
  end if;

  if v_access.state = 'invitation_pending'
    and v_access.external_invitation_id = p_external_invitation_id
    and v_access.invitation_method = p_invitation_method
    and v_access.invitation_target = p_invitation_target
  then
    return;
  end if;

  update private.external_course_access
  set external_group_id = v_expected_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      external_invitation_id = p_external_invitation_id,
      invitation_method = p_invitation_method,
      invitation_target = p_invitation_target,
      state = 'invitation_pending',
      invited_at = case
        when external_invitation_id is distinct from p_external_invitation_id
          then clock_timestamp()
        else coalesce(invited_at, clock_timestamp())
      end,
      accepted_at = null,
      last_checked_at = clock_timestamp(),
      failure_code = null,
      consecutive_membership_absences = 0
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_membership_absence (
  p_course_id  uuid,
  p_profile_id uuid
)
  returns boolean
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_absence_count integer;
begin
  perform 1
  from public.courses as course
  where course.id = p_course_id
    and course.status = 'published'
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'published_course_not_found';
  end if;

  update private.external_course_access as access_row
  set consecutive_membership_absences = access_row.consecutive_membership_absences + 1,
      last_checked_at = clock_timestamp(),
      failure_code = 'external_membership_temporarily_missing'
  from private.course_access_requests as request_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
    and access_row.state = 'active'
    and request_row.id = access_row.access_request_id
    and request_row.course_id = access_row.course_id
    and request_row.requester_profile_id = access_row.profile_id
    and request_row.status = 'approved'
  returning access_row.consecutive_membership_absences into v_absence_count;

  if not found then
    raise exception using errcode = '23503', message = 'active_external_access_not_reconcilable';
  end if;

  if v_absence_count < 3 then
    return false;
  end if;

  perform private.record_external_course_access_status(
    p_course_id,
    p_profile_id,
    'revoked',
    null
  );
  return true;
end
$function$;

alter function "private"."record_external_course_access_membership_absence"(uuid, uuid) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_status (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_state        text,
  p_failure_code text default null::text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_failure_code text := nullif(btrim(p_failure_code), '');
begin
  if p_state not in ('invitation_pending', 'sso_required', 'failed', 'revoked') then
    raise exception using errcode = '22023', message = 'invalid_external_course_access_state';
  end if;

  if p_state = 'failed' and v_failure_code is null then
    raise exception using errcode = '22023', message = 'external_access_failure_code_required';
  end if;

  perform 1
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select access_row.*
  into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_started';
  end if;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id
    and request_row.course_id = p_course_id
    and request_row.requester_profile_id = p_profile_id
    and request_row.status = 'approved';

  if not found then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  select organization.external_group_id, organization.external_group_handle
  into v_expected_external_group_id, v_expected_external_group_handle
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'external_group_not_configured';
  end if;

  if v_access.state = 'active' and p_state <> 'revoked' then
    raise exception using errcode = '55000', message = 'active_external_access_requires_confirmation';
  end if;

  if v_access.state = p_state and v_access.failure_code is not distinct from v_failure_code then
    update private.external_course_access
    set last_checked_at = clock_timestamp()
    where course_id = p_course_id and profile_id = p_profile_id;
    return;
  end if;

  update private.external_course_access
  set external_group_id = v_expected_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      state = p_state,
      invited_at = case
        when p_state in ('invitation_pending', 'sso_required') then coalesce(invited_at, clock_timestamp())
        else invited_at
      end,
      last_checked_at = clock_timestamp(),
      failure_code = v_failure_code
  where course_id = p_course_id and profile_id = p_profile_id;

  if p_state = 'revoked' then
    update public.course_memberships
    set status = 'revoked',
        revoked_at = coalesce(revoked_at, clock_timestamp()),
        suspended_at = null
    where course_id = p_course_id
      and profile_id = p_profile_id
      and created_from_access_request_id = v_request.id
      and status = 'active';

    insert into private.course_membership_events (
      course_id, profile_id, event_kind, previous_role, previous_status,
      new_role, new_status, actor_profile_id, reason
    )
    select
      p_course_id, p_profile_id, 'transitioned', membership.role, 'active',
      membership.role, 'revoked', null,
      'GitHub course organization membership no longer active'
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.profile_id = p_profile_id
      and membership.created_from_access_request_id = v_request.id
      and membership.status = 'revoked'
      and membership.revoked_at is not null
      and not exists (
        select 1
        from private.course_membership_events as event_row
        where event_row.course_id = p_course_id
          and event_row.profile_id = p_profile_id
          and event_row.event_kind = 'transitioned'
          and event_row.new_status = 'revoked'
          and event_row.reason = 'GitHub course organization membership no longer active'
      );
  end if;
end
$function$;

alter function "private"."record_external_course_access_status"(uuid, uuid, text, text) owner to "ainigma_function_owner";

create or replace function private.sync_auth_identity (
  p_identity_id uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_identity record;
  v_profile_id uuid;
  v_username text;
  v_email text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_identity_id::text, 0)
  );

  select identity_row.*
  into v_identity
  from private.auth_identities as identity_row
  where identity_row.id = p_identity_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_identity_not_found';
  end if;

  v_profile_id := private.ensure_auth_user_profile(v_identity.user_id);

  if v_identity.provider <> 'github' then
    return v_profile_id;
  end if;

  if v_identity.provider_id !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'invalid_github_numeric_subject';
  end if;

  perform private.upsert_verified_identifier(
    v_profile_id,
    'external_user_id',
    'github.com',
    1,
    v_identity.provider_id,
    coalesce(v_identity.created_at, clock_timestamp()),
    v_identity.user_id,
    v_identity.id::text
  );

  v_username := lower(btrim(coalesce(
    v_identity.identity_data ->> 'user_name',
    v_identity.identity_data ->> 'preferred_username',
    v_identity.identity_data ->> 'login'
  )));

  if nullif(v_username, '') is not null then
    update private.profile_identifiers
    set revoked_at = clock_timestamp(),
        last_verified_at = clock_timestamp()
    where profile_id = v_profile_id
      and kind = 'external_user_handle'
      and issuer = 'github.com'
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'external_user_handle',
      'github.com',
      1,
      v_username,
      coalesce(v_identity.created_at, clock_timestamp()),
      v_identity.user_id,
      v_identity.id::text
    );
  end if;

  if lower(coalesce(v_identity.identity_data ->> 'email_verified', 'false')) = 'true' then
    v_email := lower(btrim(v_identity.identity_data ->> 'email'));

    if nullif(v_email, '') is not null then
      update private.profile_identifiers
      set revoked_at = clock_timestamp(),
          last_verified_at = clock_timestamp()
      where profile_id = v_profile_id
        and kind = 'email'
        and issuer = 'github.com'
        and scheme_version = 1
        and normalized_value <> v_email
        and revoked_at is null;

      perform private.upsert_verified_identifier(
        v_profile_id,
        'email',
        'github.com',
        1,
        v_email,
        coalesce(v_identity.created_at, clock_timestamp()),
        v_identity.user_id,
        v_identity.id::text
      );
    end if;
  end if;

  return v_profile_id;
end
$function$;

create or replace function public.approve_course_access_requests (
  p_offering_key text,
  p_request_ids  uuid[] default null::uuid[]
)
  returns integer
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
  v_provider_issuer text;
begin
  select course.id, organization.provider_issuer
  into v_course_id, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if p_request_ids is not null and exists (
    select 1 from private.course_access_requests as request_row
    where request_row.id = any (p_request_ids) and request_row.course_id <> v_course_id
  ) then
    raise sqlstate 'PT400' using message = 'request_course_mismatch';
  end if;

  if exists (
    select 1
    from private.course_access_requests as request_row
    where request_row.course_id = v_course_id
      and request_row.status = 'pending'
      and (p_request_ids is null or request_row.id = any (p_request_ids))
      and not exists (
        select 1 from private.profile_identifiers as identifier
        where identifier.profile_id = request_row.requester_profile_id
          and identifier.kind = 'external_user_id'
          and identifier.issuer = v_provider_issuer
          and identifier.revoked_at is null
      )
  ) then
    raise sqlstate 'PT403' using message = 'external_identity_not_provisioned';
  end if;

  with selected as (
    select request_row.id
    from private.course_access_requests as request_row
    where request_row.course_id = v_course_id
      and request_row.status = 'pending'
      and (p_request_ids is null or request_row.id = any (p_request_ids))
    for update
  ), changed as (
    update private.course_access_requests as request_row
    set status = 'approved', decided_at = clock_timestamp(), decided_by = v_actor_profile_id
    from selected
    where request_row.id = selected.id
    returning request_row.*
  )
  insert into private.external_course_access (course_id, profile_id, access_request_id, external_user_id, state)
  select changed.course_id, changed.requester_profile_id, changed.id, identifier.normalized_value, 'not_started'
  from changed
  join private.profile_identifiers as identifier
    on identifier.profile_id = changed.requester_profile_id
   and identifier.kind = 'external_user_id'
   and identifier.issuer = v_provider_issuer
   and identifier.revoked_at is null
  on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

create or replace function public.get_my_course_repository (
  p_offering_key text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_repository private.course_repository_provisioning%rowtype;
begin
  select course.id
  into v_course_id
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  where course.offering_key = p_offering_key
    and course.status in ('published', 'archived');

  if v_course_id is null then
    raise sqlstate 'PT404' using message = 'course_membership_not_found';
  end if;

  select repository.*
  into v_repository
  from private.course_repository_provisioning as repository
  where repository.course_id = v_course_id
    and repository.profile_id = v_profile_id;

  if not found then
    return jsonb_build_object(
      'offering_key', p_offering_key,
      'state', 'not_requested'
    );
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'offering_key', p_offering_key,
    'state', v_repository.state,
    'repository_name', v_repository.repository_name,
    'repository_url', v_repository.external_repository_url,
    'failure_code', v_repository.last_error,
    'requested_at', v_repository.created_at,
    'updated_at', v_repository.updated_at
  ));
end
$function$;

create or replace function public.list_course_access_requests (
  p_offering_key         text,
  p_status               text default 'pending'::text,
  p_authorization_filter text default null::text
)
  returns table (
    request_id            uuid,
    offering_key          text,
    display_name          text,
    external_user_handle  text,
    verified_email        text,
    reason                text,
    status                text,
    authorization_status  text,
    requested_at          timestamp with time zone,
    decided_at            timestamp with time zone,
    external_access_state text
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_provider_issuer text;
begin
  select course.id, organization.provider_issuer
  into v_course_id, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key;

  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    request_row.id,
    course.offering_key,
    profile.display_name,
    (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = request_row.requester_profile_id
        and identifier.kind = 'external_user_handle'
        and identifier.issuer = v_provider_issuer
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ),
    (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = request_row.requester_profile_id
        and identifier.kind = 'email'
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ),
    request_row.reason,
    request_row.status,
    case
      when exists (
        select 1
        from private.course_roster_allowlist as allowlist
        join private.profile_identifiers as identifier
          on identifier.kind = allowlist.identifier_kind
         and identifier.issuer = allowlist.identifier_issuer
         and identifier.scheme_version = allowlist.identifier_scheme_version
         and identifier.normalized_value = allowlist.normalized_identifier_value
         and identifier.profile_id = request_row.requester_profile_id
         and identifier.revoked_at is null
        where allowlist.course_id = v_course_id
          and allowlist.status = 'active'
      ) then 'preauthorized'
      when exists (
        select 1 from private.profile_identifiers as identifier
        where identifier.profile_id = request_row.requester_profile_id
          and identifier.revoked_at is null
      ) then 'not_preauthorized'
      else 'unverified'
    end,
    request_row.requested_at,
    request_row.decided_at,
    access_row.state
  from private.course_access_requests as request_row
  join public.courses as course on course.id = request_row.course_id
  join public.profiles as profile on profile.id = request_row.requester_profile_id
  left join private.external_course_access as access_row on access_row.access_request_id = request_row.id
  where request_row.course_id = v_course_id
    and (p_status is null or request_row.status = p_status)
    and (
      p_authorization_filter is null
      or p_authorization_filter = case
        when exists (
          select 1
          from private.course_roster_allowlist as allowlist
          join private.profile_identifiers as identifier
            on identifier.kind = allowlist.identifier_kind
           and identifier.issuer = allowlist.identifier_issuer
           and identifier.scheme_version = allowlist.identifier_scheme_version
           and identifier.normalized_value = allowlist.normalized_identifier_value
           and identifier.profile_id = request_row.requester_profile_id
           and identifier.revoked_at is null
          where allowlist.course_id = v_course_id and allowlist.status = 'active'
        ) then 'preauthorized'
        when exists (
          select 1 from private.profile_identifiers as identifier
          where identifier.profile_id = request_row.requester_profile_id
            and identifier.revoked_at is null
        ) then 'not_preauthorized'
        else 'unverified'
      end
    )
  order by request_row.requested_at;
end
$function$;

alter function "public"."list_course_access_requests"(text, text, text) owner to "ainigma_function_owner";

create or replace function public.list_my_course_access_requests()
  returns table (
    offering_key          text,
    request_id            uuid,
    status                text,
    reason                text,
    requested_at          timestamp with time zone,
    decided_at            timestamp with time zone,
    external_access_state text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select course.offering_key,
     request_row.id,
     request_row.status,
     request_row.reason,
     request_row.requested_at,
     request_row.decided_at,
     access_row.state
    from ((private.course_access_requests request_row
      JOIN public.courses course on ((course.id = request_row.course_id)))
      LEFT JOIN private.external_course_access access_row on ((access_row.access_request_id = request_row.id)))
   where (request_row.requester_profile_id = private.current_profile_id())
   ORDER by request_row.requested_at desc;
end;

alter function "public"."list_my_course_access_requests"() owner to "ainigma_function_owner";

create or replace function public.request_course_access (
  p_offering_key text,
  p_reason       text default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_enrollment_mode text;
  v_provider_issuer text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id, course.enrollment_mode, organization.provider_issuer
  into v_course_id, v_enrollment_mode, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published';

  if v_course_id is null then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if v_enrollment_mode = 'closed' then
    raise sqlstate 'PT403' using message = 'course_enrollment_closed';
  end if;

  select membership.*
  into v_membership
  from public.course_memberships as membership
  where membership.course_id = v_course_id
    and membership.profile_id = v_profile_id;

  if found and v_membership.status = 'active' then
    return jsonb_build_object('state', 'active', 'offering_key', p_offering_key);
  end if;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.course_id = v_course_id
    and request_row.requester_profile_id = v_profile_id
  order by request_row.requested_at desc
  limit 1;

  if found and v_request.status in ('pending', 'approved') then
    return jsonb_build_object(
      'state', case when v_request.status = 'approved' then 'awaiting_external_access' else 'pending' end,
      'offering_key', p_offering_key,
      'request_id', v_request.id
    );
  end if;

  select
    v_enrollment_mode = 'allowlist_auto'
    and exists (
      select 1
      from private.course_roster_allowlist as allowlist
      join private.profile_identifiers as identifier
        on identifier.kind = allowlist.identifier_kind
       and identifier.issuer = allowlist.identifier_issuer
       and identifier.scheme_version = allowlist.identifier_scheme_version
       and identifier.normalized_value = allowlist.normalized_identifier_value
       and identifier.profile_id = v_profile_id
       and identifier.revoked_at is null
      where allowlist.course_id = v_course_id and allowlist.status = 'active'
    )
    and exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.profile_id = v_profile_id
        and identifier.kind = 'external_user_id'
        and identifier.issuer = v_provider_issuer
        and identifier.revoked_at is null
    )
  into v_auto_approved;

  insert into private.course_access_requests (
    course_id,
    requester_profile_id,
    reason,
    status,
    decision_source,
    decided_at
  )
  values (
    v_course_id,
    v_profile_id,
    nullif(btrim(p_reason), ''),
    case when v_auto_approved then 'approved' else 'pending' end,
    case when v_auto_approved then 'allowlist' else 'owner' end,
    case when v_auto_approved then clock_timestamp() else null end
  )
  returning * into v_request;

  if v_auto_approved then
    insert into private.external_course_access (
      course_id, profile_id, access_request_id, external_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      identifier.normalized_value,
      'not_started'
    from private.profile_identifiers as identifier
    where identifier.profile_id = v_profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = v_provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;

    return jsonb_build_object(
      'state', 'awaiting_external_access',
      'offering_key', p_offering_key,
      'request_id', v_request.id
    );
  end if;

  return jsonb_build_object(
    'state', 'pending',
    'offering_key', p_offering_key,
    'request_id', v_request.id
  );
end
$function$;

create or replace function public.request_my_course_repository (
  p_offering_key text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_access_request_id uuid;
  v_external_group_id text;
  v_external_group_handle text;
begin
  select
    course.id,
    access_row.access_request_id,
    access_row.external_group_id,
    access_row.external_group_handle
  into
    v_course_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.external_course_access as access_row
    on access_row.course_id = course.id
   and access_row.profile_id = v_profile_id
   and access_row.state = 'active'
   and access_row.external_user_handle is not null
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
   and organization.external_group_id = access_row.external_group_id
   and organization.external_group_handle = access_row.external_group_handle
  where course.offering_key = p_offering_key
    and course.status = 'published'
  for update of access_row;

  if v_course_id is null then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  insert into private.course_repository_provisioning (
    course_id,
    profile_id,
    access_request_id,
    external_group_id,
    external_group_handle
  ) values (
    v_course_id,
    v_profile_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

alter table "private"."course_definition_releases"
  add constraint "course_definition_releases_external_group_fkey" foreign key (course_definition_key) references private.course_definition_external_groups(course_definition_key)
    on delete restrict;

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_group_handle_check"
    check (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_group_id_check"
    check (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_ready_shape_check" check ((((state = 'ready'::text) AND (repository_name IS NOT NULL) AND (external_repository_id IS
    NOT NULL) AND (external_repository_url IS NOT NULL)) OR (state <> 'ready'::text)));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_repository_id_check"
    check
    (((external_repository_id IS NULL) OR ((external_repository_id = btrim(external_repository_id)) AND ((char_length(external_repository_id) >= 1) AND
    (char_length(external_repository_id) <= 255)))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_url_check"
    check
    (((external_repository_url IS NULL) OR ((external_repository_url = btrim(external_repository_url)) AND ((char_length(external_repository_url) >= 1) AND
    (char_length(external_repository_url) <= 2048)))));

alter table "private"."course_roster_allowlist"
  add constraint "course_roster_allowlist_kind_check" check ((identifier_kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'student_identifier'::text])));

alter table "private"."external_course_access"
  add constraint "external_course_access_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_access_identity_fkey" foreign key (course_id, profile_id, access_request_id, external_group_id, external_group_handle)
    references private.external_course_access(course_id, profile_id, access_request_id, external_group_id, external_group_handle) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_request_course_profile_fk" foreign key (access_request_id, course_id, profile_id)
    references private.course_access_requests(id, course_id, requester_profile_id) on delete restrict;

alter table "private"."profile_identifiers"
  add constraint "profile_identifiers_kind_check" check ((kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'external_user_handle'::text, 'student_identifier'::text])));

alter table "public"."courses"
  add constraint "courses_course_definition_external_group_fkey" foreign key (course_definition_key) references private.course_definition_external_groups(course_definition_key)
    on delete restrict;

create index course_definition_external_groups_group_id_idx on private.course_definition_external_groups using btree (external_group_id);

create unique index course_repository_provisioning_org_name_uidx on private.course_repository_provisioning using btree (external_group_id, repository_name)
  where (repository_name is not null);

create unique index course_repository_provisioning_repository_id_uidx on private.course_repository_provisioning using btree (external_repository_id)
  where (external_repository_id is not null);

create unique index external_course_access_request_uidx on private.external_course_access using btree (access_request_id);

create policy "external_course_access_function_access" on "private"."external_course_access"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

comment on column "private"."course_definition_external_groups"."external_group_handle" is 'Current provider group handle for diagnostics and display; external_group_id is authoritative.';

comment on column "private"."course_definition_external_groups"."external_group_id" is 'Stable provider group ID used for authorization; the handle is only a display snapshot.';

comment on column "private"."course_definition_external_groups"."provider_issuer" is 'Identifier issuer used to select verified profile facts for this provider instance.';

comment on column "private"."course_definition_external_groups"."provider_kind" is 'Provider adapter key, currently github; it selects the external platform implementation.';

comment on column "private"."course_repository_provisioning"."external_repository_id" is 'Stable provider repository ID; used instead of the mutable repository name for reconciliation.';

comment on column "private"."course_repository_provisioning"."repository_name" is 'Deterministic offering-specific repository name, normally submissions-<offering_key>-<user_handle>.';

comment on column "private"."external_course_access"."external_invitation_id" is 'Provider invitation ID for the current invitation attempt; acceptance must match this ID.';

comment on column "private"."external_course_access"."external_user_handle" is 'Current provider login or handle cached from verified membership; it may change and is not an identity key.';

comment on column "private"."external_course_access"."external_user_id" is 'Stable external provider account ID. This is the identity key for the offering access record.';

comment on table "private"."course_definition_external_groups" is 'The trusted external provider group configured for each reusable course definition.';

comment on table "private"."course_repository_provisioning" is 'Durable idempotent outbox for one external submissions repository per offering and profile.';

revoke all on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) from public;

grant execute on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) to "ainigma_maintenance";

revoke all on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) from public;

grant execute on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) from public;

grant execute on function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."list_external_course_access_to_reconcile"() from public;

grant execute on function "private"."list_external_course_access_to_reconcile"() to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_check_failure"(uuid, uuid, text) from public;

grant execute on function "private"."record_external_course_access_check_failure"(uuid, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) from public;

grant execute on function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_membership_absence"(uuid, uuid) from public;

grant execute on function "private"."record_external_course_access_membership_absence"(uuid, uuid) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_status"(uuid, uuid, text, text) from public;

grant execute on function "private"."record_external_course_access_status"(uuid, uuid, text, text) to "ainigma_maintenance";

revoke all on function "public"."list_course_access_requests"(text, text, text) from public;

revoke all on function "public"."list_course_access_requests"(text, text, text) from "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, text, text) to "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, text, text) to "authenticated";

revoke all on function "public"."list_my_course_access_requests"() from public;

revoke all on function "public"."list_my_course_access_requests"() from "ainigma_function_owner";

grant execute on function "public"."list_my_course_access_requests"() to "ainigma_function_owner";

grant execute on function "public"."list_my_course_access_requests"() to "authenticated";

grant select on table "private"."course_definition_external_groups" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_external_groups" to "postgres";

grant insert, select, update on table "private"."external_course_access" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."external_course_access" to "postgres";
