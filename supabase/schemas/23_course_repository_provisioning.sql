-- Durable, explicitly requested GitHub repository provisioning.

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


