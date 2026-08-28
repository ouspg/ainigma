set local check_function_bodies = off;

alter table "private"."github_course_access"
  drop constraint "github_course_access_invitation_method_check";

drop function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, text);

drop function "private"."list_github_course_access_to_reconcile"();

drop function "private"."record_github_course_access_invitation"(uuid, uuid, text, text);

alter table "private"."github_course_access"
  add column "github_organization_invitation_id" bigint;

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
      access_row.github_username,
      case
        when access_row.github_username is null then null
        when char_length('submissions-' || course.offering_key || '-' || access_row.github_username) <= 100
          then 'submissions-' || course.offering_key || '-' || access_row.github_username
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || access_row.github_username), 8) || '-' ||
          left(access_row.github_username, 20)
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
    where request_row.status = 'approved'
      and access_row.state = 'active'
      and access_row.github_username is not null
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
    access_row.github_username,
    access_row.github_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.github_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
  ;
end
$function$;

create or replace function private.confirm_github_course_access (
  p_course_id                         uuid,
  p_profile_id                        uuid,
  p_github_org_id                     bigint,
  p_github_org_slug                   text,
  p_github_organization_invitation_id bigint,
  p_github_user_id                    text,
  p_github_username                   text
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
begin
  if p_github_org_id is null
    or p_github_org_id <= 0
    or p_github_org_slug is null
    or p_github_org_slug <> btrim(p_github_org_slug)
    or char_length(p_github_org_slug) not between 1 and 255
    or p_github_organization_invitation_id is null
    or p_github_organization_invitation_id <= 0
    or p_github_user_id is null
    or p_github_user_id <> btrim(p_github_user_id)
    or p_github_user_id !~ '^[0-9]+$'
    or p_github_username is null
    or p_github_username <> btrim(p_github_username)
    or p_github_username !~ '^[A-Za-z0-9-]+$'
  then
    raise exception using errcode = '22023', message = 'invalid_github_membership_identity';
  end if;

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

  if not found
    or p_github_org_id is distinct from v_expected_github_org_id
    or p_github_org_slug is distinct from v_expected_github_org_slug
  then
    raise exception using errcode = '42501', message = 'github_organization_mismatch';
  end if;

  if v_access.github_organization_invitation_id is distinct from p_github_organization_invitation_id then
    raise exception using errcode = '42501', message = 'github_invitation_mismatch';
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

  update private.github_course_access
  set github_org_id = p_github_org_id,
      github_org_slug = v_expected_github_org_slug,
      github_user_id = p_github_user_id,
      github_username = p_github_username,
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
    'GitHub organization invitation and membership confirmed'
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

alter function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, bigint, text, text) owner to "ainigma_function_owner";

create or replace function private.list_github_course_access_to_reconcile()
  returns table (
    course_id                         uuid,
    profile_id                        uuid,
    access_request_id                 uuid,
    offering_key                      text,
    expected_github_org_id            bigint,
    expected_github_org_slug          text,
    github_user_id                    text,
    github_username                   text,
    github_organization_invitation_id bigint,
    github_email                      text,
    invitation_method                 text,
    invitation_target                 text,
    state                             text
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
    access_row.github_username,
    access_row.github_organization_invitation_id,
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
  p_course_id                         uuid,
  p_profile_id                        uuid,
  p_invitation_method                 text,
  p_invitation_target                 text,
  p_github_organization_invitation_id bigint
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_target text;
  v_expected_github_org_id bigint;
  v_expected_github_org_slug text;
begin
  if p_invitation_method not in ('email', 'github_user_id')
    or p_invitation_target is null
    or p_invitation_target <> btrim(p_invitation_target)
    or char_length(p_invitation_target) not between 1 and 512
    or p_github_organization_invitation_id is null
    or p_github_organization_invitation_id <= 0
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

  if p_invitation_method = 'email' then
    select identifier.normalized_value
    into v_expected_target
    from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'email'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;
  else
    v_expected_target := v_access.github_user_id;
  end if;

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

  if v_access.state = 'invitation_pending'
    and v_access.github_organization_invitation_id = p_github_organization_invitation_id
    and v_access.invitation_method = p_invitation_method
    and v_access.invitation_target = p_invitation_target
  then
    return;
  end if;

  update private.github_course_access
  set github_org_id = v_expected_github_org_id,
      github_org_slug = v_expected_github_org_slug,
      github_organization_invitation_id = p_github_organization_invitation_id,
      invitation_method = p_invitation_method,
      invitation_target = p_invitation_target,
      state = 'invitation_pending',
      invited_at = case
        when github_organization_invitation_id is distinct from p_github_organization_invitation_id
          then clock_timestamp()
        else coalesce(invited_at, clock_timestamp())
      end,
      accepted_at = null,
      last_checked_at = clock_timestamp(),
      failure_code = null
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_github_course_access_invitation"(uuid, uuid, text, text, bigint) owner to "ainigma_function_owner";

create or replace function private.record_github_course_access_status (
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
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_github_org_id bigint;
  v_expected_github_org_slug text;
  v_failure_code text := nullif(btrim(p_failure_code), '');
begin
  if p_state not in ('invitation_pending', 'sso_required', 'failed', 'revoked') then
    raise exception using errcode = '22023', message = 'invalid_github_course_access_state';
  end if;

  if p_state = 'failed' and v_failure_code is null then
    raise exception using errcode = '22023', message = 'github_access_failure_code_required';
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
  from private.github_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'github_access_not_started';
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

  select organization.github_org_id, organization.github_org_slug
  into v_expected_github_org_id, v_expected_github_org_slug
  from public.courses as course
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'github_organization_not_configured';
  end if;

  if v_access.state = 'active' and p_state <> 'revoked' then
    raise exception using errcode = '55000', message = 'active_github_access_requires_confirmation';
  end if;

  if v_access.state = p_state and v_access.failure_code is not distinct from v_failure_code then
    return;
  end if;

  update private.github_course_access
  set github_org_id = v_expected_github_org_id,
      github_org_slug = v_expected_github_org_slug,
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

alter table "private"."github_course_access"
  add constraint "github_course_access_invitation_id_check" check (((github_organization_invitation_id IS NULL) OR (github_organization_invitation_id > 0)));

alter table "private"."github_course_access"
  add constraint "github_course_access_invitation_method_check" check ((invitation_method = ANY (ARRAY['email'::text, 'github_user_id'::text])));

comment on column "private"."github_course_access"."github_organization_invitation_id" is 'GitHub organization invitation ID for the current invitation attempt; acceptance must match this ID.';

comment on column "private"."github_course_access"."github_user_id" is 'Stable GitHub account ID. This is the identity key for the offering access record.';

comment on column "private"."github_course_access"."github_username" is 'Current GitHub login cached from a verified membership; it may change and is not an identity key.';

revoke all on function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, bigint, text, text) from public;

grant execute on function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, bigint, text, text) to "ainigma_maintenance";

revoke all on function "private"."list_github_course_access_to_reconcile"() from public;

grant execute on function "private"."list_github_course_access_to_reconcile"() to "ainigma_maintenance";

revoke all on function "private"."record_github_course_access_invitation"(uuid, uuid, text, text, bigint) from public;

grant execute on function "private"."record_github_course_access_invitation"(uuid, uuid, text, text, bigint) to "ainigma_maintenance";
