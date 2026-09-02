-- Offering access requests and trusted roster allowlists.

create table private.course_access_requests (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete restrict,
  requester_profile_id uuid not null references public.profiles (id) on delete restrict,
  requested_role private.course_membership_role not null default 'learner',
  reason text,
  status private.course_access_request_status not null default 'pending',
  decision_source text not null default 'owner',
  requested_at timestamptz not null default clock_timestamp(),
  decided_at timestamptz,
  decided_by uuid references public.profiles (id) on delete restrict,
  decision_reason text,
  constraint course_access_requests_reason_check check (
    reason is null or (reason = btrim(reason) and char_length(reason) between 1 and 2000)
  ),
  constraint course_access_requests_decision_source_check check (
    decision_source in ('owner', 'allowlist')
  ),
  constraint course_access_requests_decision_shape_check check (
    (status in ('pending', 'cancelled') and decided_at is null and decided_by is null)
    or (status = 'approved' and decided_at is not null and (decided_by is not null or decision_source = 'allowlist'))
    or (status = 'rejected' and decided_at is not null and decided_by is not null and decision_source = 'owner')
  ),
  constraint course_access_requests_id_course_profile_unique
    unique (id, course_id, requester_profile_id)
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
  role private.course_membership_role not null default 'learner',
  source text not null,
  status text not null default 'active',
  imported_at timestamptz not null default clock_timestamp(),
  imported_by uuid references public.profiles (id) on delete restrict,
  revoked_at timestamptz,
  constraint course_roster_allowlist_kind_check check (
    identifier_kind in ('email', 'external_user_id', 'student_identifier')
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

-- Activate a learner only from an approved request. Both first-party
-- approval-only access and external-provider confirmation use this helper so
-- the request link and audit event cannot drift between workflows.
create function private.activate_course_membership_from_request(
  p_access_request_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request private.course_access_requests%rowtype;
begin
  if p_access_request_id is null then
    raise exception using errcode = '22004', message = 'access_request_id_required';
  end if;

  if p_reason is null or p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_course_membership_reason';
  end if;

  perform 1
  from public.courses as course
  join private.course_access_requests as request_row
    on request_row.course_id = course.id
  where request_row.id = p_access_request_id
  for update of course;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.id = p_access_request_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'access_request_not_found';
  end if;

  if v_request.status <> 'approved' then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  if v_request.requested_role <> 'learner' then
    raise exception using errcode = '22023', message = 'requested_role_not_supported';
  end if;

  insert into public.course_memberships (
    course_id, profile_id, role, status, created_from_access_request_id
  ) values (
    v_request.course_id, v_request.requester_profile_id, 'learner', 'active', v_request.id
  )
  on conflict (course_id, profile_id) do nothing;

  if not found then
    return;
  end if;

  insert into private.course_membership_events (
    course_id, profile_id, event_kind, new_role, new_status, actor_profile_id, reason
  ) values (
    v_request.course_id,
    v_request.requester_profile_id,
    'created',
    'learner',
    'active',
    null,
    p_reason
  );
end
$function$;
