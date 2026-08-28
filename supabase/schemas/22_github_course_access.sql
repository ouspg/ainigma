-- Offering-scoped GitHub invitations, organization membership reconciliation, and activation.

create table private.github_course_access (
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  access_request_id uuid not null,
  github_org_id bigint,
  github_org_slug text,
  github_user_id text not null,
  -- Stable GitHub user ID is authoritative. The username is the current
  -- provider API handle and a cache used for repository permissions/naming.
  github_username text,
  github_organization_invitation_id bigint,
  invitation_method text not null default 'email',
  invitation_target text,
  state text not null default 'not_started',
  invited_at timestamptz,
  accepted_at timestamptz,
  last_checked_at timestamptz,
  failure_code text,
  consecutive_membership_absences integer not null default 0,
  primary key (course_id, profile_id),
  constraint github_course_access_state_check check (
    state in ('not_started', 'invitation_pending', 'sso_required', 'active', 'failed', 'revoked')
  ),
  constraint github_course_access_org_shape_check check (
    (state = 'not_started' and github_org_id is null and github_org_slug is null)
    or (state <> 'not_started' and github_org_id is not null and github_org_slug is not null)
  ),
  constraint github_course_access_org_slug_check check (
    github_org_slug is null
    or (github_org_slug = btrim(github_org_slug) and char_length(github_org_slug) between 1 and 255)
  ),
  constraint github_course_access_user_id_check check (
    github_user_id = btrim(github_user_id) and github_user_id ~ '^[0-9]+$'
  ),
  constraint github_course_access_invitation_id_check check (
    github_organization_invitation_id is null
    or github_organization_invitation_id > 0
  ),
  constraint github_course_access_username_check check (
    github_username is null
    or (github_username = btrim(github_username) and github_username ~ '^[A-Za-z0-9-]+$')
  ),
  constraint github_course_access_invitation_method_check check (
    invitation_method in ('email', 'github_user_id')
  ),
  constraint github_course_access_invitation_target_check check (
    invitation_target is null
    or (invitation_target = btrim(invitation_target) and char_length(invitation_target) between 1 and 512)
  ),
  constraint github_course_access_failure_check check (
    failure_code is null or (failure_code = btrim(failure_code) and char_length(failure_code) between 1 and 255)
  ),
  constraint github_course_access_membership_absences_check check (
    consecutive_membership_absences >= 0
  ),
  constraint github_course_access_request_course_profile_fk foreign key (
    access_request_id,
    course_id,
    profile_id
  ) references private.course_access_requests (
    id,
    course_id,
    requester_profile_id
  ) on delete restrict,
  constraint github_course_access_repository_identity_unique unique (
    course_id,
    profile_id,
    access_request_id,
    github_org_id,
    github_org_slug
  )
);

comment on column private.github_course_access.github_user_id is
  'Stable GitHub account ID. This is the identity key for the offering access record.';
comment on column private.github_course_access.github_username is
  'Current GitHub login cached from a verified membership; it may change and is not an identity key.';
comment on column private.github_course_access.github_organization_invitation_id is
  'GitHub organization invitation ID for the current invitation attempt; acceptance must match this ID.';

create unique index github_course_access_request_uidx
  on private.github_course_access (access_request_id);


-- Return only approved external-access records that a trusted GitHub worker may
-- reconcile. The stable GitHub user ID is authoritative; the username is only
-- the provider API lookup handle and is verified again by the worker.
create function private.list_github_course_access_to_reconcile()
returns table (
  course_id uuid,
  profile_id uuid,
  access_request_id uuid,
  offering_key text,
  expected_github_org_id bigint,
  expected_github_org_slug text,
  github_user_id text,
  github_username text,
  github_organization_invitation_id bigint,
  github_email text,
  invitation_method text,
  invitation_target text,
  state text
)
language sql
stable
security definer
set search_path = ''
as $function$
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

-- Record an invitation sent through GitHub. The target must be the currently
-- verified identifier for this profile; the worker cannot invite an arbitrary
-- email address or username for an offering.
create function private.record_github_course_access_invitation(
  p_course_id uuid,
  p_profile_id uuid,
  p_invitation_method text,
  p_invitation_target text,
  p_github_organization_invitation_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_access private.github_course_access%rowtype;
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


-- Record that an external invitation was sent or that polling observed a
-- non-active provider state. This never creates local course membership.
create function private.record_github_course_access_status(
  p_course_id uuid,
  p_profile_id uuid,
  p_state text,
  p_failure_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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

-- Preserve the last confirmed access state when GitHub itself cannot be checked.
-- A transient provider or SSO error must not revoke or downgrade active access.
create function private.record_github_course_access_check_failure(
  p_course_id uuid,
  p_profile_id uuid,
  p_failure_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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

-- Treat absence from one organization snapshot as inconclusive. Three
-- consecutive complete snapshots must omit an active member before local
-- offering access is revoked.
create function private.record_github_course_access_membership_absence(
  p_course_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
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

  update private.github_course_access as access_row
  set consecutive_membership_absences = access_row.consecutive_membership_absences + 1,
      last_checked_at = clock_timestamp(),
      failure_code = 'github_membership_temporarily_missing'
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


-- Called only by the trusted GitHub integration after it has confirmed the
-- expected invitation ID and stable user ID are an active membership in the
-- course organization. The username is a current provider API handle, not
-- the identity key.
create function private.confirm_github_course_access(
  p_course_id uuid,
  p_profile_id uuid,
  p_github_org_id bigint,
  p_github_org_slug text,
  p_github_organization_invitation_id bigint,
  p_github_user_id text,
  p_github_username text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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

  select organization.github_org_id, organization.github_org_slug
  into v_expected_github_org_id, v_expected_github_org_slug
  from public.courses as course
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
  for update of course;

  if not found then
    raise exception using errcode = '55000', message = 'course_offering_not_reconcilable';
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

  if p_github_org_id is distinct from v_expected_github_org_id
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

