set local check_function_bodies = off;

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_access_fkey";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_error_check";

alter table "private"."course_repository_provisioning"
  drop constraint "course_repository_provisioning_state_check";

drop function "private"."fail_course_repository_provisioning"(uuid, uuid, uuid, text, integer);

alter table "private"."github_course_access"
  add column "consecutive_membership_absences" integer not null default 0;

alter table "private"."course_repository_provisioning"
  alter column "next_attempt_at" drop not null;

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
      next_attempt_at = null,
      last_error = null,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
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
    and course.status = 'published'
    and access_row.state <> 'revoked';
$function$;

create or replace function private.record_course_repository_provisioning_failure (
  p_course_id   uuid,
  p_profile_id  uuid,
  p_lease_token uuid,
  p_error_code  text,
  p_retryable   boolean
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_repository private.course_repository_provisioning%rowtype;
  v_retry_after_seconds integer;
begin
  if p_error_code is null
    or p_error_code <> btrim(p_error_code)
    or char_length(p_error_code) not between 1 and 255
    or p_retryable is null
  then
    raise exception using errcode = '22023', message = 'invalid_repository_failure';
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

  if v_repository.state in ('retry_wait', 'blocked')
    and v_repository.last_error = p_error_code
  then
    return;
  end if;

  if v_repository.state <> 'provisioning'
    or v_repository.lease_token is distinct from p_lease_token
  then
    raise exception using errcode = '55000', message = 'repository_lease_invalid';
  end if;

  v_retry_after_seconds := least(
    3600,
    30 * (2 ^ least(greatest(v_repository.attempt_count - 1, 0), 7))::integer
  );

  update private.course_repository_provisioning
  set state = case
        when p_retryable and v_repository.attempt_count < 8 then 'retry_wait'
        else 'blocked'
      end,
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = case
        when p_retryable and v_repository.attempt_count < 8
          then clock_timestamp() + make_interval(secs => v_retry_after_seconds)
        else null
      end,
      last_error = p_error_code,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) owner to "ainigma_function_owner";

create or replace function private.record_github_course_access_check_failure (
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
    raise exception using errcode = '22023', message = 'invalid_github_access_failure_code';
  end if;

  update private.github_course_access as access_row
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
    raise exception using errcode = '23503', message = 'github_access_not_reconcilable';
  end if;
end
$function$;

alter function "private"."record_github_course_access_check_failure"(uuid, uuid, text) owner to "ainigma_function_owner";

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
      failure_code = null,
      consecutive_membership_absences = 0
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

create or replace function private.record_github_course_access_membership_absence (
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
  update private.github_course_access as access_row
  set consecutive_membership_absences = access_row.consecutive_membership_absences + 1,
      last_checked_at = clock_timestamp(),
      failure_code = 'github_membership_temporarily_missing'
  from private.course_access_requests as request_row,
       public.courses as course
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
    and access_row.state = 'active'
    and request_row.id = access_row.access_request_id
    and request_row.course_id = access_row.course_id
    and request_row.requester_profile_id = access_row.profile_id
    and request_row.status = 'approved'
    and course.id = access_row.course_id
    and course.status = 'published'
  returning access_row.consecutive_membership_absences into v_absence_count;

  if not found then
    raise exception using errcode = '23503', message = 'active_github_access_not_reconcilable';
  end if;

  if v_absence_count < 3 then
    return false;
  end if;

  perform private.record_github_course_access_status(
    p_course_id,
    p_profile_id,
    'revoked',
    null
  );
  return true;
end
$function$;

alter function "private"."record_github_course_access_membership_absence"(uuid, uuid) owner to "ainigma_function_owner";

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
    update private.github_course_access
    set last_checked_at = clock_timestamp()
    where course_id = p_course_id and profile_id = p_profile_id;
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
    'repository_url', v_repository.github_repository_url,
    'failure_code', v_repository.last_error,
    'requested_at', v_repository.created_at,
    'updated_at', v_repository.updated_at
  ));
end
$function$;

alter function "public"."get_my_course_repository"(text) owner to "ainigma_function_owner";

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
  v_github_org_id bigint;
  v_github_org_slug text;
begin
  select
    course.id,
    access_row.access_request_id,
    access_row.github_org_id,
    access_row.github_org_slug
  into
    v_course_id,
    v_access_request_id,
    v_github_org_id,
    v_github_org_slug
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.github_course_access as access_row
    on access_row.course_id = course.id
   and access_row.profile_id = v_profile_id
   and access_row.state = 'active'
   and access_row.github_username is not null
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
   and request_row.status = 'approved'
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
   and organization.github_org_id = access_row.github_org_id
   and organization.github_org_slug = access_row.github_org_slug
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
    github_org_id,
    github_org_slug
  ) values (
    v_course_id,
    v_profile_id,
    v_access_request_id,
    v_github_org_id,
    v_github_org_slug
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

alter function "public"."request_my_course_repository"(text) owner to "ainigma_function_owner";

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_error_check" check ((((state = ANY (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS
    NOT NULL) AND (last_error = btrim(last_error)) AND ((char_length(last_error) >= 1) AND (char_length(last_error) <= 1000))) OR
    ((state <> ALL (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS NULL))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_next_attempt_check"
    check ((((state = ANY (ARRAY['queued'::text, 'retry_wait'::text, 'provisioning'::text])) AND (next_attempt_at IS
    NOT NULL)) OR ((state = ANY (ARRAY['ready'::text, 'blocked'::text])) AND (next_attempt_at IS NULL))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_state_check"
    check ((state = ANY (ARRAY['queued'::text, 'provisioning'::text, 'retry_wait'::text, 'ready'::text, 'blocked'::text])));

alter table "private"."github_course_access"
  add constraint "github_course_access_membership_absences_check" check ((consecutive_membership_absences >= 0));

alter table "private"."github_course_access"
  add constraint "github_course_access_repository_identity_unique" unique (course_id, profile_id, access_request_id, github_org_id, github_org_slug);

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_access_identity_fkey" foreign key (course_id, profile_id, access_request_id, github_org_id, github_org_slug)
    references private.github_course_access(course_id, profile_id, access_request_id, github_org_id, github_org_slug) on delete restrict;

revoke all on function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) from public;

grant execute on function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) to "ainigma_maintenance";

revoke all on function "private"."record_github_course_access_check_failure"(uuid, uuid, text) from public;

grant execute on function "private"."record_github_course_access_check_failure"(uuid, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."record_github_course_access_membership_absence"(uuid, uuid) from public;

grant execute on function "private"."record_github_course_access_membership_absence"(uuid, uuid) to "ainigma_maintenance";

revoke all on function "public"."get_my_course_repository"(text) from public;

revoke all on function "public"."get_my_course_repository"(text) from "ainigma_function_owner";

grant execute on function "public"."get_my_course_repository"(text) to "ainigma_function_owner";

grant execute on function "public"."get_my_course_repository"(text) to "authenticated";

revoke all on function "public"."request_my_course_repository"(text) from public;

revoke all on function "public"."request_my_course_repository"(text) from "ainigma_function_owner";

grant execute on function "public"."request_my_course_repository"(text) to "ainigma_function_owner";

grant execute on function "public"."request_my_course_repository"(text) to "authenticated";
