-- Offering access requests and trusted roster allowlists.

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
  role text not null default 'learner',
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


