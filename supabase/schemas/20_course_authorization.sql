-- Declarative course authorization lifecycle: memberships, requests, trusted rosters,
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

create trigger course_definition_releases_reject_mutation
before update or delete on private.course_definition_releases
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

-- Durable outbox/state machine for one offering-specific submissions repository
-- per profile. External GitHub calls happen outside the database transaction.
create table private.course_repository_provisioning (
  course_id uuid not null,
  profile_id uuid not null,
  access_request_id uuid not null,
  github_org_id bigint not null,
  github_org_slug text not null,
  repository_name text,
  github_repository_id bigint,
  github_repository_url text,
  state text not null default 'queued',
  attempt_count integer not null default 0,
  lease_token uuid,
  lease_expires_at timestamptz,
  next_attempt_at timestamptz default clock_timestamp(),
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (course_id, profile_id),
  constraint course_repository_provisioning_access_identity_fkey foreign key (
    course_id,
    profile_id,
    access_request_id,
    github_org_id,
    github_org_slug
  ) references private.github_course_access (
    course_id,
    profile_id,
    access_request_id,
    github_org_id,
    github_org_slug
  ) on delete restrict,
  constraint course_repository_provisioning_request_fkey foreign key (
    access_request_id, course_id, profile_id
  ) references private.course_access_requests (id, course_id, requester_profile_id) on delete restrict,
  constraint course_repository_provisioning_org_id_check check (github_org_id > 0),
  constraint course_repository_provisioning_org_slug_check check (
    github_org_slug = btrim(github_org_slug)
    and char_length(github_org_slug) between 1 and 255
  ),
  constraint course_repository_provisioning_name_check check (
    repository_name is null
    or (repository_name = btrim(repository_name) and char_length(repository_name) between 1 and 100)
  ),
  constraint course_repository_provisioning_repository_id_check check (
    github_repository_id is null or github_repository_id > 0
  ),
  constraint course_repository_provisioning_url_check check (
    github_repository_url is null
    or (github_repository_url = btrim(github_repository_url) and char_length(github_repository_url) between 1 and 2048)
  ),
  constraint course_repository_provisioning_state_check check (
    state in ('queued', 'provisioning', 'retry_wait', 'ready', 'blocked')
  ),
  constraint course_repository_provisioning_attempt_check check (attempt_count >= 0),
  constraint course_repository_provisioning_lease_check check (
    (state = 'provisioning' and lease_token is not null and lease_expires_at is not null)
    or (state <> 'provisioning' and lease_token is null and lease_expires_at is null)
  ),
  constraint course_repository_provisioning_ready_shape_check check (
    (state = 'ready'
      and repository_name is not null
      and github_repository_id is not null
      and github_repository_url is not null)
    or state <> 'ready'
  ),
  constraint course_repository_provisioning_next_attempt_check check (
    (state in ('queued', 'retry_wait', 'provisioning') and next_attempt_at is not null)
    or (state in ('ready', 'blocked') and next_attempt_at is null)
  ),
  constraint course_repository_provisioning_error_check check (
    (
      state in ('retry_wait', 'blocked')
      and last_error is not null
      and last_error = btrim(last_error)
      and char_length(last_error) between 1 and 1000
    )
    or (state not in ('retry_wait', 'blocked') and last_error is null)
  )
);

comment on table private.course_repository_provisioning is
  'Durable idempotent outbox for one GitHub submissions repository per offering and profile.';
comment on column private.course_repository_provisioning.repository_name is
  'Deterministic offering-specific GitHub repository name, normally submissions-<offering_key>-<username>.';
comment on column private.course_repository_provisioning.github_repository_id is
  'Stable GitHub repository ID; used instead of the mutable repository name for reconciliation.';

create unique index course_repository_provisioning_repository_id_uidx
  on private.course_repository_provisioning (github_repository_id)
  where github_repository_id is not null;
create unique index course_repository_provisioning_org_name_uidx
  on private.course_repository_provisioning (github_org_id, repository_name)
  where repository_name is not null;
create index course_repository_provisioning_claim_idx
  on private.course_repository_provisioning (state, next_attempt_at, lease_expires_at, updated_at);
create trigger course_repository_provisioning_set_updated_at
before update on private.course_repository_provisioning
for each row execute function private.set_updated_at();
alter table private.course_access_requests enable row level security;
alter table private.course_access_requests force row level security;
alter table private.course_roster_allowlist enable row level security;
alter table private.course_roster_allowlist force row level security;
alter table private.github_course_access enable row level security;
alter table private.github_course_access force row level security;
alter table private.course_repository_provisioning enable row level security;
alter table private.course_repository_provisioning force row level security;

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
create policy course_repository_provisioning_function_access
on private.course_repository_provisioning
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);

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

-- Claim repository work with a short lease. A worker may crash after claiming;
-- another worker can retry it after the lease expires.
create function private.claim_course_repository_provisioning(
  p_limit integer default 25,
  p_course_id uuid default null,
  p_profile_id uuid default null
)
returns table (
  course_id uuid,
  profile_id uuid,
  access_request_id uuid,
  offering_key text,
  github_org_id bigint,
  github_org_slug text,
  repository_name text,
  github_repository_id bigint,
  github_repository_url text,
  github_username text,
  github_user_id text,
  lease_token uuid,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $function$
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

-- Complete a repository job only with the lease that claimed it. Repeating a
-- completion for a repository already marked ready is harmless.
create function private.complete_course_repository_provisioning(
  p_course_id uuid,
  p_profile_id uuid,
  p_lease_token uuid,
  p_github_repository_id bigint,
  p_github_repository_name text,
  p_github_repository_url text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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

-- Record a bounded worker failure classification. Retryable failures use
-- exponential backoff and eventually become blocked instead of retrying forever.
create function private.record_course_repository_provisioning_failure(
  p_course_id uuid,
  p_profile_id uuid,
  p_lease_token uuid,
  p_error_code text,
  p_retryable boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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

create function private.register_course_definition_release(
  p_course_definition_key text,
  p_source_commit_sha text,
  p_course_release_digest text,
  p_artifact_ref text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_release private.course_definition_releases%rowtype;
begin
  insert into private.course_definition_releases (
    course_definition_key,
    source_commit_sha,
    course_release_digest,
    artifact_ref
  )
  values (
    p_course_definition_key,
    p_source_commit_sha,
    p_course_release_digest,
    p_artifact_ref
  )
  on conflict (course_definition_key, course_release_digest) do nothing
  returning * into v_release;

  if v_release.id is null then
    select release.*
    into strict v_release
    from private.course_definition_releases as release
    where release.course_definition_key = p_course_definition_key
      and release.course_release_digest = p_course_release_digest;

    if v_release.source_commit_sha <> p_source_commit_sha
      or v_release.artifact_ref <> p_artifact_ref
    then
      raise exception using
        errcode = '23505',
        message = 'course_definition_release_metadata_mismatch';
    end if;
  end if;

  return v_release.id;
end
$function$;

-- The Ainigma compiler calls this after admitting and deploying a release. Ended offerings are
-- represented by the archived status and deliberately retain their existing release pointer.
create function private.advance_open_course_offerings_to_release(
  p_course_definition_release_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_course_definition_key text;
  v_updated_count integer;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  update public.courses as course
  set course_definition_release_id = p_course_definition_release_id
  where course.course_definition_key = v_course_definition_key
    and course.status <> 'archived'
    and course.course_definition_release_id <> p_course_definition_release_id;

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end
$function$;

-- Branching is a compiler/control-plane operation. It creates a new operational space and owner
-- membership from an exact existing definition release; it never copies the source directory.
create function private.branch_course_offering(
  p_offering_key text,
  p_course_definition_release_id uuid,
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
  v_course_definition_key text;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  if not exists (
    select 1 from public.profiles as profile where profile.id = p_owner_profile_id
  ) then
    raise exception using errcode = '23503', message = 'owner_profile_not_found';
  end if;

  insert into public.courses (
    offering_key,
    course_definition_key,
    course_definition_release_id,
    code,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_offering_key,
    v_course_definition_key,
    p_course_definition_release_id,
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
            'offering_key', course.offering_key,
            'course_definition_key', course.course_definition_key,
            'course_definition_release_id', course.course_definition_release_id,
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
          order by course.offering_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and membership.status = 'active'
          and (
            course.status in ('published', 'archived')
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
            'offering_key', course.offering_key,
            'course_definition_release_id', course.course_definition_release_id,
            'course_status', course.status,
            'membership_role', membership.role,
            'membership_status', membership.status,
            'created_at', membership.created_at,
            'suspended_at', membership.suspended_at,
            'revoked_at', membership.revoked_at
          )
          order by course.offering_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and not (
            membership.status = 'active'
            and (
              course.status in ('published', 'archived')
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

create function public.list_course_roster(p_offering_key text)
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
  where course.offering_key = p_offering_key;

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
create function public.request_course_access(p_offering_key text, p_reason text default null)
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
      'state', case when v_request.status = 'approved' then 'awaiting_github_access' else 'pending' end,
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

-- Return only the caller's offering-specific repository state. This read does
-- not create a provisioning job, so course pages can render an explicit button.
create function public.get_my_course_repository(p_offering_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
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

-- Enqueue one optional submissions repository for the authenticated learner.
-- Identity, offering, request, and organization values are derived entirely
-- from trusted rows. Repeating the request returns the same durable job.
create function public.request_my_course_repository(p_offering_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

create function public.list_my_course_access_requests()
returns table (
  offering_key text,
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
    course.offering_key,
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
  p_offering_key text,
  p_status text default 'pending',
  p_authorization_filter text default null
)
returns table (
  request_id uuid,
  offering_key text,
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
begin
  select course.id into v_course_id
  from public.courses as course
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
  p_offering_key text,
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
  select course.id into v_course_id
  from public.courses as course
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
  p_offering_key text,
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
  select course.id into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key;
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
-- The function owner receives only the relation access needed by the
-- security-definer functions. It cannot authenticate directly.
grant select, insert on private.course_definition_releases to ainigma_function_owner;
grant select on private.course_definition_github_organizations to ainigma_function_owner;
grant select, insert, update on public.courses to ainigma_function_owner;
grant select, insert, update on public.course_memberships to ainigma_function_owner;
grant select, insert on private.course_membership_events to ainigma_function_owner;
grant usage, select on sequence private.course_membership_events_id_seq to ainigma_function_owner;
grant select, insert, update on private.course_access_requests to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.course_roster_allowlist to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.github_course_access to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.course_repository_provisioning to ainigma_function_owner;

alter function private.has_course_role(uuid, text[]) owner to ainigma_function_owner;
alter function private.can_view_profile(uuid) owner to ainigma_function_owner;
alter function private.register_course_definition_release(text, text, text, text) owner to ainigma_function_owner;
alter function private.advance_open_course_offerings_to_release(uuid) owner to ainigma_function_owner;
alter function private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text) owner to ainigma_function_owner;
alter function private.add_course_membership(uuid, uuid, text, uuid, text) owner to ainigma_function_owner;
alter function private.transition_course_membership(uuid, uuid, text, text, uuid, text) owner to ainigma_function_owner;
alter function private.transfer_course_ownership(uuid, uuid, uuid, text) owner to ainigma_function_owner;
alter function private.list_github_course_access_to_reconcile() owner to ainigma_function_owner;
alter function private.record_github_course_access_invitation(uuid, uuid, text, text, bigint) owner to ainigma_function_owner;
alter function private.record_github_course_access_status(uuid, uuid, text, text) owner to ainigma_function_owner;
alter function private.record_github_course_access_check_failure(uuid, uuid, text) owner to ainigma_function_owner;
alter function private.record_github_course_access_membership_absence(uuid, uuid) owner to ainigma_function_owner;
alter function private.claim_course_repository_provisioning(integer, uuid, uuid) owner to ainigma_function_owner;
alter function private.complete_course_repository_provisioning(uuid, uuid, uuid, bigint, text, text) owner to ainigma_function_owner;
alter function private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean) owner to ainigma_function_owner;
alter function public.list_my_courses() owner to ainigma_function_owner;
alter function public.list_course_roster(text) owner to ainigma_function_owner;
alter function private.confirm_github_course_access(uuid, uuid, bigint, text, bigint, text, text) owner to ainigma_function_owner;
alter function public.request_course_access(text, text) owner to ainigma_function_owner;
alter function public.get_my_course_repository(text) owner to ainigma_function_owner;
alter function public.request_my_course_repository(text) owner to ainigma_function_owner;
alter function public.list_my_course_access_requests() owner to ainigma_function_owner;
alter function public.list_course_access_requests(text, text, text) owner to ainigma_function_owner;
alter function public.approve_course_access_requests(text, uuid[]) owner to ainigma_function_owner;
alter function public.reject_course_access_requests(text, uuid[], text) owner to ainigma_function_owner;

revoke all on function
  private.reject_mutation(),
  private.has_course_role(uuid, text[]),
  private.can_view_profile(uuid),
  private.register_course_definition_release(text, text, text, text),
  private.advance_open_course_offerings_to_release(uuid),
  private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text),
  private.add_course_membership(uuid, uuid, text, uuid, text),
  private.transition_course_membership(uuid, uuid, text, text, uuid, text),
  private.transfer_course_ownership(uuid, uuid, uuid, text),
  private.list_github_course_access_to_reconcile(),
  private.record_github_course_access_invitation(uuid, uuid, text, text, bigint),
  private.record_github_course_access_status(uuid, uuid, text, text),
  private.record_github_course_access_check_failure(uuid, uuid, text),
  private.record_github_course_access_membership_absence(uuid, uuid),
  private.claim_course_repository_provisioning(integer, uuid, uuid),
  private.complete_course_repository_provisioning(uuid, uuid, uuid, bigint, text, text),
  private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean),
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_my_courses(),
  public.list_course_roster(text),
  private.confirm_github_course_access(uuid, uuid, bigint, text, bigint, text, text),
  public.request_course_access(text, text),
  public.get_my_course_repository(text),
  public.request_my_course_repository(text),
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
grant execute on function private.register_course_definition_release(text, text, text, text) to ainigma_maintenance;
grant execute on function private.advance_open_course_offerings_to_release(uuid) to ainigma_maintenance;
grant execute on function private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text) to ainigma_maintenance;
grant execute on function private.add_course_membership(uuid, uuid, text, uuid, text) to ainigma_maintenance;
grant execute on function private.transition_course_membership(uuid, uuid, text, text, uuid, text) to ainigma_maintenance;
grant execute on function private.transfer_course_ownership(uuid, uuid, uuid, text) to ainigma_maintenance;
grant execute on function private.list_github_course_access_to_reconcile() to ainigma_maintenance;
grant execute on function private.record_github_course_access_invitation(uuid, uuid, text, text, bigint) to ainigma_maintenance;
grant execute on function private.record_github_course_access_status(uuid, uuid, text, text) to ainigma_maintenance;
grant execute on function private.record_github_course_access_check_failure(uuid, uuid, text) to ainigma_maintenance;
grant execute on function private.record_github_course_access_membership_absence(uuid, uuid) to ainigma_maintenance;
grant execute on function private.claim_course_repository_provisioning(integer, uuid, uuid) to ainigma_maintenance;
grant execute on function private.complete_course_repository_provisioning(uuid, uuid, uuid, bigint, text, text) to ainigma_maintenance;
grant execute on function private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean) to ainigma_maintenance;
grant execute on function private.confirm_github_course_access(uuid, uuid, bigint, text, bigint, text, text) to ainigma_maintenance;

grant execute on function
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_my_courses(),
  public.list_course_roster(text),
  public.request_course_access(text, text),
  public.get_my_course_repository(text),
  public.request_my_course_repository(text),
  public.list_my_course_access_requests()
to authenticated;
grant execute on function
  public.list_course_access_requests(text, text, text),
  public.approve_course_access_requests(text, uuid[]),
  public.reject_course_access_requests(text, uuid[], text)
to authenticated;

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
  private.github_course_access,
  private.course_repository_provisioning
  from public, anon, authenticated, service_role;
revoke all on sequence private.course_membership_events_id_seq
  from public, anon, authenticated, service_role;
