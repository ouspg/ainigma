-- Course authorization lifecycle: memberships, requests, trusted rosters,
-- GitHub organization access, and the RPC-only browser API.
create table public.course_memberships (
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  role text not null,
  status text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  suspended_at timestamptz,
  revoked_at timestamptz,
  primary key (course_id, profile_id),
  constraint course_memberships_role_check check (
    role in ('owner', 'instructor', 'learner')
  ),
  constraint course_memberships_status_check check (
    status in ('active', 'suspended', 'revoked')
  ),
  constraint course_memberships_status_timestamps_check check (
    (status = 'active' and suspended_at is null and revoked_at is null)
    or (status = 'suspended' and suspended_at is not null and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  )
);


create index course_memberships_profile_status_role_idx
  on public.course_memberships (profile_id, status, role, course_id);

create index course_memberships_course_role_status_idx
  on public.course_memberships (course_id, role, status);

create table private.course_membership_events (
  id bigint generated always as identity primary key,
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  event_kind text not null,
  previous_role text,
  previous_status text,
  new_role text not null,
  new_status text not null,
  actor_profile_id uuid references public.profiles (id) on delete restrict,
  reason text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint course_membership_events_kind_check check (
    event_kind in ('created', 'transitioned')
  ),
  constraint course_membership_events_previous_role_check check (
    previous_role is null or previous_role in ('owner', 'instructor', 'learner')
  ),
  constraint course_membership_events_previous_status_check check (
    previous_status is null or previous_status in ('active', 'suspended', 'revoked')
  ),
  constraint course_membership_events_new_role_check check (
    new_role in ('owner', 'instructor', 'learner')
  ),
  constraint course_membership_events_new_status_check check (
    new_status in ('active', 'suspended', 'revoked')
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
create table private.course_access_requests (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  requester_profile_id uuid not null references public.profiles (id) on delete restrict,
  requested_role text not null default 'learner',
  reason text,
  status text not null default 'pending',
  decision_source text not null default 'owner',
  requested_at timestamptz not null default clock_timestamp(),
  decided_at timestamptz,
  decided_by uuid references public.profiles (id) on delete restrict,
  decision_reason text,
  constraint course_access_requests_role_check check (requested_role = 'learner'),
  constraint course_access_requests_reason_check check (
    reason is null or (reason = btrim(reason) and char_length(reason) between 1 and 2000)
  ),
  constraint course_access_requests_status_check check (
    status in ('pending', 'approved', 'rejected', 'cancelled')
  ),
  constraint course_access_requests_decision_source_check check (
    decision_source in ('owner', 'allowlist')
  ),
  constraint course_access_requests_decision_shape_check check (
    (status in ('pending', 'cancelled') and decided_at is null and decided_by is null)
    or (status = 'approved' and decided_at is not null and (decided_by is not null or decision_source = 'allowlist'))
    or (status = 'rejected' and decided_at is not null and decided_by is not null and decision_source = 'owner')
  )
);

create unique index course_access_requests_pending_uidx
  on private.course_access_requests (course_id, requester_profile_id)
  where status = 'pending';

create index course_access_requests_course_status_idx
  on private.course_access_requests (course_id, status, requested_at);

alter table public.course_memberships
  add column created_from_access_request_id uuid;

alter table public.course_memberships
  add constraint course_memberships_access_request_fk
  foreign key (created_from_access_request_id)
  references private.course_access_requests (id)
  on delete restrict;

create unique index course_memberships_access_request_uidx
  on public.course_memberships (created_from_access_request_id)
  where created_from_access_request_id is not null;

create table private.course_roster_allowlist (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  identifier_kind text not null,
  identifier_issuer text not null,
  identifier_scheme_version integer not null,
  normalized_identifier_value text not null,
  role text not null default 'learner',
  source text not null,
  status text not null default 'active',
  imported_at timestamptz not null default clock_timestamp(),
  imported_by uuid references public.profiles (id) on delete restrict,
  revoked_at timestamptz,
  constraint course_roster_allowlist_kind_check check (
    identifier_kind in ('email', 'github_user_id', 'student_identifier')
  ),
  constraint course_roster_allowlist_issuer_check check (
    identifier_issuer = btrim(identifier_issuer)
    and char_length(identifier_issuer) between 1 and 255
  ),
  constraint course_roster_allowlist_scheme_check check (identifier_scheme_version > 0),
  constraint course_roster_allowlist_value_check check (
    normalized_identifier_value = btrim(normalized_identifier_value)
    and char_length(normalized_identifier_value) between 1 and 512
  ),
  constraint course_roster_allowlist_role_check check (role = 'learner'),
  constraint course_roster_allowlist_source_check check (
    source = btrim(source) and char_length(source) between 1 and 255
  ),
  constraint course_roster_allowlist_status_check check (status in ('active', 'revoked')),
  constraint course_roster_allowlist_revoked_shape_check check (
    (status = 'active' and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  )
);

create unique index course_roster_allowlist_active_uidx
  on private.course_roster_allowlist (
    course_id,
    identifier_kind,
    identifier_issuer,
    identifier_scheme_version,
    normalized_identifier_value
  )
  where status = 'active';

create index course_roster_allowlist_course_idx
  on private.course_roster_allowlist (course_id, status);

create table private.github_course_access (
  course_id uuid not null references public.courses (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  access_request_id uuid not null references private.course_access_requests (id) on delete restrict,
  github_org_id bigint,
  github_org_slug text,
  github_user_id text not null,
  state text not null default 'not_started',
  invited_at timestamptz,
  accepted_at timestamptz,
  last_checked_at timestamptz,
  failure_code text,
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
  constraint github_course_access_failure_check check (
    failure_code is null or (failure_code = btrim(failure_code) and char_length(failure_code) between 1 and 255)
  )
);

create unique index github_course_access_request_uidx
  on private.github_course_access (access_request_id);
alter table private.course_access_requests enable row level security;
alter table private.course_access_requests force row level security;
alter table private.course_roster_allowlist enable row level security;
alter table private.course_roster_allowlist force row level security;
alter table private.github_course_access enable row level security;
alter table private.github_course_access force row level security;

create policy course_access_requests_function_access
on private.course_access_requests
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);

create policy course_roster_allowlist_function_access
on private.course_roster_allowlist
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);

create policy github_course_access_function_access
on private.github_course_access
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);
create function private.has_course_role(p_course_id uuid, p_roles text[])
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

create function private.create_course_with_initial_owner(
  p_course_key text,
  p_definition_key text,
  p_code text,
  p_owner_profile_id uuid,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_external_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
begin
  if not exists (
    select 1 from public.profiles as profile where profile.id = p_owner_profile_id
  ) then
    raise exception using errcode = '23503', message = 'owner_profile_not_found';
  end if;

  insert into public.courses (
    course_key,
    definition_key,
    code,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_course_key,
    p_definition_key,
    p_code,
    p_starts_at,
    p_ends_at,
    p_external_url
  )
  returning id into v_course_id;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (v_course_id, p_owner_profile_id, 'owner', 'active');

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
    v_course_id,
    p_owner_profile_id,
    'created',
    'owner',
    'active',
    p_owner_profile_id,
    'initial course owner'
  );

  return v_course_id;
end
$function$;

create function private.add_course_membership(
  p_course_id uuid,
  p_profile_id uuid,
  p_role text,
  p_actor_profile_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_role text;
begin
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

create function private.transition_course_membership(
  p_course_id uuid,
  p_profile_id uuid,
  p_new_role text,
  p_new_status text,
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
  v_actor_role text;
  v_active_owner_count integer;
begin
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
create function public.list_my_courses()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return jsonb_build_object(
    'courses', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'course_key', course.course_key,
            'definition_key', course.definition_key,
            'code', course.code,
            'course_status', course.status,
            'membership_role', membership.role,
            'membership_status', membership.status,
            'starts_at', course.starts_at,
            'ends_at', course.ends_at,
            'external_url', course.external_url,
            'created_at', course.created_at,
            'updated_at', course.updated_at
          )
          order by course.course_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and membership.status = 'active'
          and (
            course.status = 'published'
            or (
              course.status = 'draft'
              and membership.role in ('owner', 'instructor')
            )
          )
      ),
      '[]'::jsonb
    ),
    'inactive_memberships', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'course_key', course.course_key,
            'course_status', course.status,
            'membership_role', membership.role,
            'membership_status', membership.status,
            'created_at', membership.created_at,
            'suspended_at', membership.suspended_at,
            'revoked_at', membership.revoked_at
          )
          order by course.course_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and not (
            membership.status = 'active'
            and (
              course.status = 'published'
              or (
                course.status = 'draft'
                and membership.role in ('owner', 'instructor')
              )
            )
          )
      ),
      '[]'::jsonb
    )
  );
end
$function$;

create function public.list_course_roster(p_course_key text)
returns table (
  display_name text,
  role text,
  status text,
  created_at timestamptz,
  suspended_at timestamptz,
  revoked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
begin
  select course.id
  into v_course_id
  from public.courses as course
  where course.course_key = p_course_key;

  -- Use one response for missing and unauthorized courses to avoid revealing
  -- whether an offering exists through the RPC.
  if v_course_id is null
    or not private.has_course_role(v_course_id, array['owner', 'instructor']::text[])
  then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    profile.display_name,
    membership.role,
    membership.status,
    membership.created_at,
    membership.suspended_at,
    membership.revoked_at
  from public.course_memberships as membership
  join public.profiles as profile
    on profile.id = membership.profile_id
  where membership.course_id = v_course_id
  order by membership.created_at, profile.id;
end
$function$;
create function public.request_course_access(p_course_key text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_enrollment_mode text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id, course.enrollment_mode
  into v_course_id, v_enrollment_mode
  from public.courses as course
  where course.course_key = p_course_key
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
    return jsonb_build_object('state', 'active', 'course_key', p_course_key);
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
      'state', case when v_request.status = 'approved' then 'awaiting_github_access' else 'pending' end,
      'course_key', p_course_key,
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
        and identifier.kind = 'github_user_id'
        and identifier.issuer = 'github.com'
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
    insert into private.github_course_access (
      course_id, profile_id, access_request_id, github_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      identifier.normalized_value,
      'not_started'
    from private.profile_identifiers as identifier
    where identifier.profile_id = v_profile_id
      and identifier.kind = 'github_user_id'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;

    return jsonb_build_object(
      'state', 'awaiting_github_access',
      'course_key', p_course_key,
      'request_id', v_request.id
    );
  end if;

  return jsonb_build_object(
    'state', 'pending',
    'course_key', p_course_key,
    'request_id', v_request.id
  );
end
$function$;

create function public.list_my_course_access_requests()
returns table (
  course_key text,
  request_id uuid,
  status text,
  reason text,
  requested_at timestamptz,
  decided_at timestamptz,
  github_access_state text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    course.course_key,
    request_row.id,
    request_row.status,
    request_row.reason,
    request_row.requested_at,
    request_row.decided_at,
    access_row.state
  from private.course_access_requests as request_row
  join public.courses as course on course.id = request_row.course_id
  left join private.github_course_access as access_row
    on access_row.access_request_id = request_row.id
  where request_row.requester_profile_id = private.current_profile_id()
  order by request_row.requested_at desc;
$function$;

create function public.list_course_access_requests(
  p_course_key text,
  p_status text default 'pending',
  p_authorization_filter text default null
)
returns table (
  request_id uuid,
  course_key text,
  display_name text,
  github_username text,
  verified_email text,
  reason text,
  status text,
  authorization_status text,
  requested_at timestamptz,
  decided_at timestamptz,
  github_access_state text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
  v_profile_id uuid := private.current_profile_id();
begin
  select course.id into v_course_id
  from public.courses as course
  where course.course_key = p_course_key;

  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    request_row.id,
    course.course_key,
    profile.display_name,
    (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = request_row.requester_profile_id
        and identifier.kind = 'github_username'
        and identifier.issuer = 'github.com'
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
  left join private.github_course_access as access_row on access_row.access_request_id = request_row.id
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

create function public.approve_course_access_requests(
  p_course_key text,
  p_request_ids uuid[] default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
begin
  select course.id into v_course_id from public.courses as course where course.course_key = p_course_key;
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
          and identifier.kind = 'github_user_id'
          and identifier.issuer = 'github.com'
          and identifier.revoked_at is null
      )
  ) then
    raise sqlstate 'PT403' using message = 'github_identity_not_provisioned';
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
  insert into private.github_course_access (course_id, profile_id, access_request_id, github_user_id, state)
  select changed.course_id, changed.requester_profile_id, changed.id, identifier.normalized_value, 'not_started'
  from changed
  join private.profile_identifiers as identifier
    on identifier.profile_id = changed.requester_profile_id
   and identifier.kind = 'github_user_id'
   and identifier.issuer = 'github.com'
   and identifier.revoked_at is null
  on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

create function public.reject_course_access_requests(
  p_course_key text,
  p_request_ids uuid[] default null,
  p_decision_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
begin
  select course.id into v_course_id from public.courses as course where course.course_key = p_course_key;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  update private.course_access_requests as request_row
  set status = 'rejected', decided_at = clock_timestamp(), decided_by = v_actor_profile_id,
      decision_reason = nullif(btrim(p_decision_reason), '')
  where request_row.course_id = v_course_id
    and request_row.status = 'pending'
    and (p_request_ids is null or request_row.id = any (p_request_ids));

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

-- Called only by the trusted GitHub integration after it has confirmed the
-- expected stable user ID is an active member of the course organization.
create function private.confirm_github_course_access(
  p_course_id uuid,
  p_profile_id uuid,
  p_github_org_id bigint,
  p_github_org_slug text,
  p_github_user_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
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
      github_org_slug = p_github_org_slug,
      github_user_id = p_github_user_id,
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
end
$function$;
-- The function owner receives only the relation access needed by the
-- security-definer functions. It cannot authenticate directly.
grant usage on schema public, private to ainigma_function_owner;
grant select, insert, update on public.courses to ainigma_function_owner;
grant select, insert, update on public.course_memberships to ainigma_function_owner;
grant select, insert on private.course_membership_events to ainigma_function_owner;
grant usage, select on sequence private.course_membership_events_id_seq to ainigma_function_owner;
grant select, insert, update on private.course_access_requests to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.course_roster_allowlist to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.github_course_access to ainigma_function_owner, ainigma_maintenance;
grant ainigma_function_owner to postgres;
grant create on schema public, private to ainigma_function_owner;

alter function private.has_course_role(uuid, text[]) owner to ainigma_function_owner;
alter function private.can_view_profile(uuid) owner to ainigma_function_owner;
alter function private.create_course_with_initial_owner(text, text, text, uuid, timestamptz, timestamptz, text) owner to ainigma_function_owner;
alter function private.add_course_membership(uuid, uuid, text, uuid, text) owner to ainigma_function_owner;
alter function private.transition_course_membership(uuid, uuid, text, text, uuid, text) owner to ainigma_function_owner;
alter function public.list_my_courses() owner to ainigma_function_owner;
alter function public.list_course_roster(text) owner to ainigma_function_owner;
alter function private.confirm_github_course_access(uuid, uuid, bigint, text, text) owner to ainigma_function_owner;
alter function public.request_course_access(text, text) owner to ainigma_function_owner;
alter function public.list_my_course_access_requests() owner to ainigma_function_owner;
alter function public.list_course_access_requests(text, text, text) owner to ainigma_function_owner;
alter function public.approve_course_access_requests(text, uuid[]) owner to ainigma_function_owner;
alter function public.reject_course_access_requests(text, uuid[], text) owner to ainigma_function_owner;
revoke create on schema public, private from ainigma_function_owner;

set role ainigma_function_owner;
revoke all on function
  private.reject_mutation(),
  private.has_course_role(uuid, text[]),
  private.can_view_profile(uuid),
  private.create_course_with_initial_owner(text, text, text, uuid, timestamptz, timestamptz, text),
  private.add_course_membership(uuid, uuid, text, uuid, text),
  private.transition_course_membership(uuid, uuid, text, text, uuid, text),
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_my_courses(),
  public.list_course_roster(text),
  private.confirm_github_course_access(uuid, uuid, bigint, text, text),
  public.request_course_access(text, text),
  public.list_my_course_access_requests(),
  public.list_course_access_requests(text, text, text),
  public.approve_course_access_requests(text, uuid[]),
  public.reject_course_access_requests(text, uuid[], text)
from public, anon, authenticated, service_role, ainigma_maintenance;

grant execute on function private.current_profile_id() to authenticated;
grant execute on function private.has_course_role(uuid, text[]) to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;
grant execute on function private.ensure_auth_user_profile(uuid) to ainigma_maintenance;
grant execute on function private.sync_auth_identity(uuid) to ainigma_maintenance;
grant execute on function private.reconcile_auth_users() to ainigma_maintenance;
grant execute on function private.reconcile_auth_identities() to ainigma_maintenance;
grant execute on function private.report_identity_anomalies() to ainigma_maintenance;
grant execute on function private.create_course_with_initial_owner(text, text, text, uuid, timestamptz, timestamptz, text) to ainigma_maintenance;
grant execute on function private.add_course_membership(uuid, uuid, text, uuid, text) to ainigma_maintenance;
grant execute on function private.transition_course_membership(uuid, uuid, text, text, uuid, text) to ainigma_maintenance;
grant execute on function private.confirm_github_course_access(uuid, uuid, bigint, text, text) to ainigma_maintenance;

grant execute on function
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_my_courses(),
  public.list_course_roster(text),
  public.request_course_access(text, text),
  public.list_my_course_access_requests()
to authenticated;
grant execute on function
  public.list_course_access_requests(text, text, text),
  public.approve_course_access_requests(text, uuid[]),
  public.reject_course_access_requests(text, uuid[], text)
to authenticated;
reset role;
revoke ainigma_function_owner from postgres;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.courses enable row level security;
alter table public.courses force row level security;
alter table public.course_memberships enable row level security;
alter table public.course_memberships force row level security;

-- Internal functions operate under this NOLOGIN role. Explicit policies avoid
-- recursive browser policies without giving the role BYPASSRLS.
create policy profiles_function_owner_access
on public.profiles
for all
to ainigma_function_owner
using (true)
with check (true);

create policy courses_function_owner_access
on public.courses
for all
to ainigma_function_owner
using (true)
with check (true);

create policy course_memberships_function_owner_access
on public.course_memberships
for all
to ainigma_function_owner
using (true)
with check (true);

create policy profiles_select_authorized
on public.profiles
for select
to authenticated
using ((select private.can_view_profile(id)));

create policy profiles_update_own_display_name
on public.profiles
for update
to authenticated
using (id = (select private.current_profile_id()))
with check (id = (select private.current_profile_id()));

create policy courses_select_enrolled
on public.courses
for select
to authenticated
using (
  (
    status = 'published'
    and (select private.has_course_role(id, array['owner', 'instructor', 'learner']::text[]))
  )
  or (
    status = 'draft'
    and (select private.has_course_role(id, array['owner', 'instructor']::text[]))
  )
);

create policy course_memberships_select_authorized
on public.course_memberships
for select
to authenticated
using (
  profile_id = (select private.current_profile_id())
  or (select private.has_course_role(course_id, array['owner', 'instructor']::text[]))
);

grant usage on schema public to authenticated;

revoke all on public.profiles, public.courses, public.course_memberships
  from public, anon, authenticated, service_role;
revoke all on private.auth_users,
  private.auth_identities,
  private.auth_user_links,
  private.profile_identifiers,
  private.course_membership_events,
  private.course_access_requests,
  private.course_roster_allowlist,
  private.github_course_access
  from public, anon, authenticated, service_role;
revoke all on sequence private.course_membership_events_id_seq
  from public, anon, authenticated, service_role;
