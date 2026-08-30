-- Course membership state, immutable audit events, authorization helpers, and membership operations.

create table public.course_memberships (
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  role private.course_membership_role not null,
  status private.course_membership_status not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  suspended_at timestamptz,
  revoked_at timestamptz,
  primary key (course_id, profile_id),
  constraint course_memberships_status_timestamps_check check (
    (status = 'active' and suspended_at is null and revoked_at is null)
    or (status = 'suspended' and suspended_at is not null and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  ),
  constraint course_memberships_owner_status_check check (
    role <> 'owner' or status = 'active'
  )
);


create index course_memberships_profile_status_role_idx
  on public.course_memberships (profile_id, status, role, course_id);

create index course_memberships_course_role_status_idx
  on public.course_memberships (course_id, role, status);

create unique index course_memberships_one_active_owner_uidx
  on public.course_memberships (course_id)
  where role = 'owner' and status = 'active';

create table private.course_membership_events (
  id bigint generated always as identity primary key,
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  event_kind text not null,
  previous_role private.course_membership_role,
  previous_status private.course_membership_status,
  new_role private.course_membership_role not null,
  new_status private.course_membership_status not null,
  actor_profile_id uuid references public.profiles (id) on delete restrict,
  reason text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint course_membership_events_kind_check check (
    event_kind in ('created', 'transitioned')
  ),
  constraint course_membership_events_reason_check check (
    reason = btrim(reason) and char_length(reason) between 1 and 2000
  ),
  constraint course_membership_events_shape_check check (
    (event_kind = 'created' and previous_role is null and previous_status is null)
    or (event_kind = 'transitioned' and previous_role is not null and previous_status is not null)
  )
);

create index course_membership_events_course_created_idx
  on private.course_membership_events (course_id, created_at desc);

create index course_membership_events_profile_created_idx
  on private.course_membership_events (profile_id, created_at desc);

-- Membership history is evidence: corrections append a new event instead of rewriting the past.
create function private.reject_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception using
    errcode = '55000',
    message = format('%I.%I is append-only', tg_table_schema, tg_table_name);
end
$function$;
create trigger course_membership_events_reject_mutation
before update or delete on private.course_membership_events
for each row execute function private.reject_mutation();

create trigger course_definition_releases_reject_mutation
before update or delete on private.course_definition_releases
for each row execute function private.reject_mutation();

-- Role checks derive the caller internally; null filters deny without requiring an authenticated identity.
create function private.has_course_role(p_course_id uuid, p_roles private.course_membership_role[])
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid;
begin
  if p_course_id is null or coalesce(cardinality(p_roles), 0) = 0 then
    return false;
  end if;

  v_profile_id := private.current_profile_id();

  return exists (
    select 1
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.profile_id = v_profile_id
      and membership.status = 'active'
      and membership.role = any (p_roles)
  );
end
$function$;

-- Profiles are private unless they are the caller or share a course where the caller is active staff;
-- null targets deny without invoking the authenticated-profile resolver.
create function private.can_view_profile(p_profile_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid;
begin
  if p_profile_id is null then
    return false;
  end if;

  v_profile_id := private.current_profile_id();

  if p_profile_id = v_profile_id then
    return true;
  end if;

  return exists (
    select 1
    from public.course_memberships as staff_membership
    join public.course_memberships as roster_membership
      on roster_membership.course_id = staff_membership.course_id
    where staff_membership.profile_id = v_profile_id
      and staff_membership.status = 'active'
      and staff_membership.role in ('owner', 'instructor')
      and roster_membership.profile_id = p_profile_id
  );
end
$function$;


-- Staff authority is asymmetric: instructors may admit learners, while only owners may add staff.
create function private.add_course_membership(
  p_course_id uuid,
  p_profile_id uuid,
  p_role private.course_membership_role,
  p_actor_profile_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_role private.course_membership_role;
begin
  if p_role is null or p_role not in ('instructor', 'learner') then
    if p_role = 'owner' then
      raise exception using errcode = '42501', message = 'course_owner_transfer_required';
    end if;
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (p_role in ('owner', 'instructor') and v_actor_role <> 'owner')
    or (p_role = 'learner' and v_actor_role not in ('owner', 'instructor'))
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (p_course_id, p_profile_id, p_role, 'active');

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'created',
    p_role,
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;

-- Every state change is serialized per course and records the previous and resulting membership state.
create function private.transition_course_membership(
  p_course_id uuid,
  p_profile_id uuid,
  p_new_role private.course_membership_role,
  p_new_status private.course_membership_status,
  p_actor_profile_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_membership public.course_memberships%rowtype;
  v_actor_role private.course_membership_role;
  v_active_owner_count integer;
begin
  if p_new_role is null or p_new_role not in ('owner', 'instructor', 'learner') then
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  if p_new_role = 'owner' then
    raise exception using errcode = '42501', message = 'course_owner_transfer_required';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (
      p_new_role in ('owner', 'instructor')
      and v_actor_role <> 'owner'
    )
    or (
      p_new_role = 'learner'
      and v_actor_role not in ('owner', 'instructor')
    )
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  select membership.*
  into v_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_membership_not_found';
  end if;

  if v_actor_role = 'instructor' and v_membership.role <> 'learner' then
    raise exception using errcode = '42501', message = 'course_staff_admin_required';
  end if;

  if v_membership.role = p_new_role and v_membership.status = p_new_status then
    return;
  end if;

  if v_membership.role = 'owner'
    and v_membership.status = 'active'
    and (p_new_role <> 'owner' or p_new_status <> 'active')
  then
    select count(*)
    into v_active_owner_count
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.role = 'owner'
      and membership.status = 'active';

    if v_active_owner_count <= 1 then
      raise exception using errcode = '23514', message = 'course_requires_active_owner';
    end if;
  end if;

  update public.course_memberships
  set role = p_new_role,
      status = p_new_status,
      suspended_at = case when p_new_status = 'suspended' then clock_timestamp() else null end,
      revoked_at = case when p_new_status = 'revoked' then clock_timestamp() else null end
  where course_id = p_course_id
    and profile_id = p_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'transitioned',
    v_membership.role,
    v_membership.status,
    p_new_role,
    p_new_status,
    p_actor_profile_id,
    p_reason
  );
end
$function$;

-- Ownership transfer preserves exactly one active owner and accepts only an active instructor as successor.
create function private.transfer_course_ownership(
  p_course_id uuid,
  p_new_owner_profile_id uuid,
  p_actor_profile_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_owner_profile_id uuid;
  v_target_membership public.course_memberships%rowtype;
begin
  if p_course_id is null or p_new_owner_profile_id is null or p_actor_profile_id is null then
    raise exception using errcode = '22004', message = 'course_ownership_transfer_arguments_required';
  end if;

  if p_reason is null or p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_course_membership_reason';
  end if;

  -- All membership mutations lock the course row, so ownership changes are
  -- serialized with staff and learner membership changes.
  perform 1
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.profile_id
  into v_current_owner_profile_id
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.role = 'owner'
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'course_requires_active_owner';
  end if;

  if p_actor_profile_id <> v_current_owner_profile_id then
    raise exception using errcode = '42501', message = 'course_owner_required';
  end if;

  if p_new_owner_profile_id = v_current_owner_profile_id then
    return;
  end if;

  select membership.*
  into v_target_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_new_owner_profile_id
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_owner_target_membership_not_found';
  end if;

  if v_target_membership.role <> 'instructor' then
    raise exception using errcode = '42501', message = 'course_owner_target_must_be_instructor';
  end if;

  -- Demote first so the partial unique index can enforce one active owner
  -- throughout the transaction, then promote the selected instructor.
  update public.course_memberships
  set role = 'instructor'
  where course_id = p_course_id
    and profile_id = v_current_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_current_owner_profile_id,
    'transitioned',
    'owner',
    'active',
    'instructor',
    'active',
    p_actor_profile_id,
    p_reason
  );

  update public.course_memberships
  set role = 'owner'
  where course_id = p_course_id
    and profile_id = p_new_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_target_membership.profile_id,
    'transitioned',
    v_target_membership.role,
    v_target_membership.status,
    'owner',
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;
