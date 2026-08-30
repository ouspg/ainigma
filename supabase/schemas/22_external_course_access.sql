-- Offering-scoped external invitations, group membership reconciliation, and activation.

create table private.external_course_access (
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  access_request_id uuid not null,
  external_group_id text,
  external_group_handle text,
  external_user_id text not null,
  -- Stable external user ID is authoritative. The handle is the current
  -- provider API handle and a cache used for repository permissions/naming.
  external_user_handle text,
  external_invitation_id text,
  invitation_method text not null default 'email',
  invitation_target text,
  state text not null default 'not_started',
  invited_at timestamptz,
  accepted_at timestamptz,
  last_checked_at timestamptz,
  failure_code text,
  consecutive_membership_absences integer not null default 0,
  primary key (course_id, profile_id),
  constraint external_course_access_state_check check (
    state in ('not_started', 'invitation_pending', 'sso_required', 'active', 'failed', 'revoked')
  ),
  constraint external_course_access_group_shape_check check (
    (state = 'not_started' and external_group_id is null and external_group_handle is null)
    or (state <> 'not_started' and external_group_id is not null and external_group_handle is not null)
  ),
  constraint external_course_access_group_handle_check check (
    external_group_handle is null
    or (external_group_handle = btrim(external_group_handle) and char_length(external_group_handle) between 1 and 255)
  ),
  constraint external_course_access_user_id_check check (
    external_user_id = btrim(external_user_id)
    and char_length(external_user_id) between 1 and 255
  ),
  constraint external_course_access_invitation_id_check check (
    external_invitation_id is null
    or (external_invitation_id = btrim(external_invitation_id)
      and char_length(external_invitation_id) between 1 and 255)
  ),
  constraint external_course_access_user_handle_check check (
    external_user_handle is null
    or (external_user_handle = btrim(external_user_handle)
      and char_length(external_user_handle) between 1 and 255
      and external_user_handle !~ '[[:space:]]')
  ),
  constraint external_course_access_invitation_method_check check (
    invitation_method in ('email', 'external_user_id')
  ),
  constraint external_course_access_invitation_target_check check (
    invitation_target is null
    or (invitation_target = btrim(invitation_target) and char_length(invitation_target) between 1 and 512)
  ),
  constraint external_course_access_failure_check check (
    failure_code is null or (failure_code = btrim(failure_code) and char_length(failure_code) between 1 and 255)
  ),
  constraint external_course_access_membership_absences_check check (
    consecutive_membership_absences >= 0
  ),
  constraint external_course_access_request_course_profile_fk foreign key (
    access_request_id,
    course_id,
    profile_id
  ) references private.course_access_requests (
    id,
    course_id,
    requester_profile_id
  ) on delete restrict,
  constraint external_course_access_repository_identity_unique unique (
    course_id,
    profile_id,
    access_request_id,
    external_group_id,
    external_group_handle
  )
);

comment on column private.external_course_access.external_user_id is
  'Stable external provider account ID. This is the identity key for the offering access record.';
comment on column private.external_course_access.external_user_handle is
  'Current provider login or handle cached from verified membership; it may change and is not an identity key.';
comment on column private.external_course_access.external_invitation_id is
  'Provider invitation ID for the current invitation attempt; acceptance must match this ID.';

create unique index external_course_access_request_uidx
  on private.external_course_access (access_request_id);


-- Return only approved external-access records that a trusted provider worker may
-- reconcile. The stable external user ID is authoritative; the handle is only
-- the provider API lookup handle and is verified again by the worker.
create function private.list_external_course_access_to_reconcile()
returns table (
  course_id uuid,
  profile_id uuid,
  access_request_id uuid,
  offering_key text,
  provider_kind text,
  provider_issuer text,
  expected_external_group_id text,
  expected_external_group_handle text,
  external_user_id text,
  external_user_handle text,
  external_invitation_id text,
  external_email text,
  invitation_method text,
  invitation_target text,
  state text
)
language sql
stable
security definer
set search_path = ''
begin atomic
  select
    access_row.course_id,
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
  from private.external_course_access as access_row
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
  join public.courses as course on course.id = access_row.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = access_row.profile_id
      and identifier.kind = 'email'
      and identifier.issuer = organization.provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as email on true
  where request_row.status = 'approved'
    and course.status = 'published'
    and access_row.state <> 'revoked';
end;

-- Record an invitation sent through the configured provider. Email targets are
-- restricted to the institution's approved domains and may be supplied when a
-- profile's verified email is not available yet. Stable external IDs remain
-- tied to the approved profile.
create function private.record_external_course_access_invitation(
  p_course_id uuid,
  p_profile_id uuid,
  p_invitation_method text,
  p_invitation_target text,
  p_external_invitation_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_email_domain text;
  v_email_domain_enforced boolean;
  v_email_domain_allowed boolean;
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

  if p_invitation_method = 'email' then
    p_invitation_target := lower(p_invitation_target);
    v_email_domain := split_part(p_invitation_target, '@', 2);
    if p_invitation_target !~ '^[^@[:space:]]+@[^@[:space:]]+$'
      or v_email_domain ~ '(^[.]|[.]$|[.][.])' then
      raise exception using errcode = '22023', message = 'email_domain_not_allowed';
    end if;

    select organization.email_domain_enforced,
           exists (
             select 1
             from private.course_definition_external_email_domains as domain
             where domain.course_definition_key = organization.course_definition_key
               and (v_email_domain = domain.domain_suffix
                 or v_email_domain like '%.' || domain.domain_suffix)
           )
    into v_email_domain_enforced, v_email_domain_allowed
    from public.courses as course
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = course.course_definition_key
    where course.id = p_course_id;

    if coalesce(v_email_domain_enforced, true)
      and not coalesce(v_email_domain_allowed, false) then
      raise exception using errcode = '22023', message = 'email_domain_not_allowed';
    end if;
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

  if p_invitation_method <> 'email' then
    v_expected_target := v_access.external_user_id;
    if v_expected_target is null or v_expected_target <> p_invitation_target then
      raise exception using errcode = '42501', message = 'external_invitation_identity_mismatch';
    end if;
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


-- Record that an external invitation was sent or that polling observed a
-- non-active provider state. This never creates local course membership.
create function private.record_external_course_access_status(
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

-- Preserve the last confirmed access state when the provider cannot be checked.
-- A transient provider or SSO error must not revoke or downgrade active access.
create function private.record_external_course_access_check_failure(
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

-- Treat absence from one organization snapshot as inconclusive. Three
-- consecutive complete snapshots must omit an active member before local
-- offering access is revoked.
create function private.record_external_course_access_membership_absence(
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


-- Called only by the trusted provider integration after it has confirmed the
-- expected invitation ID and stable user ID are an active membership in the
-- course organization. The username is a current provider API handle, not
-- the identity key.
create function private.confirm_external_course_access(
  p_course_id uuid,
  p_profile_id uuid,
  p_external_group_id text,
  p_external_group_handle text,
  p_external_invitation_id text,
  p_external_user_id text,
  p_external_user_handle text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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
