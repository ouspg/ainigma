SET local check_function_bodies = off;

ALTER TABLE "private"."course_repository_provisioning"
  DROP CONSTRAINT "course_repository_provisioning_access_identity_fkey";

ALTER TABLE "private"."course_repository_provisioning"
  DROP CONSTRAINT "course_repository_provisioning_request_fkey";

ALTER TABLE "private"."course_repository_provisioning"
  ADD COLUMN "course_definition_key" text NOT NULL;

CREATE TYPE "private"."course_membership_verification" AS ENUM (
  'external_membership',
  'approval_only'
);

ALTER TABLE "public"."courses"
  ADD COLUMN "membership_verification" private.course_membership_verification NOT NULL DEFAULT 'external_membership'::private.course_membership_verification;

CREATE OR REPLACE FUNCTION private.activate_course_membership_from_request (
  p_access_request_id uuid,
  p_reason            text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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

ALTER FUNCTION "private"."activate_course_membership_from_request"(uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.claim_course_repository_provisioning (
  p_limit      integer DEFAULT 25,
  p_course_id  uuid    DEFAULT NULL::uuid,
  p_profile_id uuid    DEFAULT NULL::uuid
)
  RETURNS TABLE (
    course_id               uuid,
    profile_id              uuid,
    access_request_id       uuid,
    offering_key            text,
    provider_kind           text,
    external_group_id       text,
    external_group_handle   text,
    repository_name         text,
    external_repository_id  text,
    external_repository_url text,
    external_user_handle    text,
    external_user_id        text,
    lease_token             uuid,
    attempt_count           integer
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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
      organization.provider_kind,
      repository.external_group_id,
      repository.external_group_handle,
      repository.external_repository_id,
      repository.external_repository_url,
      coalesce(access_row.external_user_id, provider_identity.normalized_value),
      coalesce(access_row.external_user_handle, provider_handle.normalized_value),
      case
        when coalesce(access_row.external_user_handle, provider_handle.normalized_value) is null then null
        when char_length('submissions-' || course.offering_key || '-' || coalesce(access_row.external_user_handle, provider_handle.normalized_value)) <= 100
          then 'submissions-' || course.offering_key || '-' || coalesce(access_row.external_user_handle, provider_handle.normalized_value)
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || coalesce(access_row.external_user_handle, provider_handle.normalized_value)), 8) || '-' ||
          left(coalesce(access_row.external_user_handle, provider_handle.normalized_value), 20)
      end as generated_repository_name
    from private.course_repository_provisioning as repository
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
     and course.course_definition_key = repository.course_definition_key
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = repository.course_definition_key
    left join private.external_course_access as access_row
      on access_row.course_id = repository.course_id
     and access_row.profile_id = repository.profile_id
     and access_row.external_group_id = repository.external_group_id
     and access_row.external_group_handle = repository.external_group_handle
    left join lateral (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = repository.profile_id
        and identifier.kind = 'external_user_id'
        and identifier.issuer = organization.provider_issuer
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ) as provider_identity on true
    left join lateral (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = repository.profile_id
        and identifier.kind = 'external_user_handle'
        and identifier.issuer = organization.provider_issuer
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ) as provider_handle on true
    where request_row.status = 'approved'
      and (
        course.membership_verification = 'approval_only'
        or (
          access_row.state = 'active'
          and access_row.external_user_handle is not null
          and access_row.failure_code is null
          and access_row.last_checked_at >= clock_timestamp() - interval '5 minutes'
        )
      )
      and coalesce(access_row.external_user_handle, provider_handle.normalized_value) is not null
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
    organization.provider_kind,
    claimed.external_group_id,
    claimed.external_group_handle,
    claimed.repository_name,
    claimed.external_repository_id,
    claimed.external_repository_url,
    coalesce(access_row.external_user_handle, provider_handle.normalized_value),
    coalesce(access_row.external_user_id, provider_identity.normalized_value),
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  left join private.external_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
   and access_row.external_group_id = claimed.external_group_id
   and access_row.external_group_handle = claimed.external_group_handle
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = claimed.profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = organization.provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as provider_identity on true
  left join lateral (
    select identifier.normalized_value
    from private.profile_identifiers as identifier
    where identifier.profile_id = claimed.profile_id
      and identifier.kind = 'external_user_handle'
      and identifier.issuer = organization.provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1
  ) as provider_handle on true
  ;
end
$function$;

CREATE OR REPLACE FUNCTION private.confirm_external_course_access (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_external_group_id      text,
  p_external_group_handle  text,
  p_external_invitation_id text,
  p_external_user_id       text,
  p_external_user_handle   text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_provider_issuer text;
  v_membership_verification private.course_membership_verification;
begin
  if p_external_group_id is null
    or p_external_group_id <> btrim(p_external_group_id)
    or char_length(p_external_group_id) not between 1 and 255
    or p_external_group_handle is null
    or p_external_group_handle <> btrim(p_external_group_handle)
    or char_length(p_external_group_handle) not between 1 and 255
    or (p_external_invitation_id is not null and (
      p_external_invitation_id <> btrim(p_external_invitation_id)
      or char_length(p_external_invitation_id) not between 1 and 255
    ))
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
         organization.provider_issuer,
         course.membership_verification
  into v_expected_external_group_id,
       v_expected_external_group_handle,
       v_provider_issuer,
       v_membership_verification
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
  for update of course;

  if not found then
    raise exception using errcode = '55000', message = 'course_offering_not_reconcilable';
  end if;

  if v_membership_verification <> 'external_membership' then
    raise exception using errcode = '42501', message = 'external_access_not_required';
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

  if v_access.external_invitation_id is distinct from p_external_invitation_id
  then
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

  perform private.activate_course_membership_from_request(
    v_request.id,
    case when p_external_invitation_id is null
      then 'Existing platform organization membership confirmed'
      else 'Platform organization invitation and membership confirmed'
    end
  );

end
$function$;

CREATE OR REPLACE FUNCTION private.reconcile_auth_identities()
  RETURNS TABLE (
    auth_identity_id uuid,
    status           text,
    detail           text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_identity_id uuid;
begin
  for v_identity_id in
    select identity_row.id
    from private.auth_identities as identity_row
    order by identity_row.created_at, identity_row.id
  loop
    auth_identity_id := v_identity_id;

    begin
      perform private.sync_auth_identity(v_identity_id);
      status := 'synced';
      detail := null;
    exception when others then
      status := 'error';
      detail := sqlstate || ':' || sqlerrm;
    end;

    return next;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION private.record_external_course_access_invitation (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_invitation_method      private.external_invitation_method,
  p_invitation_target      text,
  p_external_invitation_id text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_email_domain text;
  v_email_domain_enforced boolean;
  v_email_domain_allowed boolean;
  v_membership_verification private.course_membership_verification;
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

  select course.membership_verification
  into v_membership_verification
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  if v_membership_verification <> 'external_membership' then
    raise exception using errcode = '42501', message = 'external_access_not_required';
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

CREATE OR REPLACE FUNCTION private.sync_auth_identity (
  p_identity_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_identity record;
  v_profile_id uuid;
  v_provider_issuer text;
  v_external_user_id text;
  v_username text;
  v_email text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_identity_id::text, 0)
  );

  select identity_row.*
  into v_identity
  from private.auth_identities as identity_row
  where identity_row.id = p_identity_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_identity_not_found';
  end if;

  v_profile_id := private.ensure_auth_user_profile(v_identity.user_id);

  v_external_user_id := btrim(coalesce(v_identity.provider_id, ''));
  if v_external_user_id = '' then
    raise exception using errcode = '22023', message = 'external_subject_required';
  end if;

  if v_identity.provider = 'github' and v_external_user_id !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'invalid_github_numeric_subject';
  end if;

  v_provider_issuer := coalesce(
    nullif(btrim(v_identity.identity_data ->> 'iss'), ''),
    case when v_identity.provider = 'github' then 'github.com' else btrim(v_identity.provider) end
  );

  perform private.upsert_verified_identifier(
    v_profile_id,
    'external_user_id',
    v_provider_issuer,
    1,
    v_external_user_id,
    coalesce(v_identity.created_at, clock_timestamp()),
    v_identity.user_id,
    v_identity.id::text
  );

  if v_identity.provider <> 'github' then
    return v_profile_id;
  end if;

  v_username := lower(btrim(coalesce(
    v_identity.identity_data ->> 'user_name',
    v_identity.identity_data ->> 'preferred_username',
    v_identity.identity_data ->> 'login'
  )));

  if nullif(v_username, '') is not null then
    update private.profile_identifiers
    set revoked_at = clock_timestamp(),
        last_verified_at = clock_timestamp()
    where profile_id = v_profile_id
      and kind = 'external_user_handle'
      and issuer = 'github.com'
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'external_user_handle',
      'github.com',
      1,
      v_username,
      coalesce(v_identity.created_at, clock_timestamp()),
      v_identity.user_id,
      v_identity.id::text
    );
  end if;

  if lower(coalesce(v_identity.identity_data ->> 'email_verified', 'false')) = 'true' then
    v_email := lower(btrim(v_identity.identity_data ->> 'email'));

    if nullif(v_email, '') is not null then
      update private.profile_identifiers
      set revoked_at = clock_timestamp(),
          last_verified_at = clock_timestamp()
      where profile_id = v_profile_id
        and kind = 'email'
        and issuer = 'github.com'
        and scheme_version = 1
        and normalized_value <> v_email
        and revoked_at is null;

      perform private.upsert_verified_identifier(
        v_profile_id,
        'email',
        'github.com',
        1,
        v_email,
        coalesce(v_identity.created_at, clock_timestamp()),
        v_identity.user_id,
        v_identity.id::text
      );
    end if;
  end if;

  return v_profile_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.approve_course_access_requests (
  p_offering_key text,
  p_request_ids  uuid[] DEFAULT NULL::uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
  v_provider_issuer text;
  v_membership_verification private.course_membership_verification;
  v_changed_request_ids uuid[];
  v_request_id uuid;
begin
  select course.id, organization.provider_issuer, course.membership_verification
  into v_course_id, v_provider_issuer, v_membership_verification
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
  for update of course;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::private.course_membership_role[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if p_request_ids is not null and exists (
    select 1 from private.course_access_requests as request_row
    where request_row.id = any (p_request_ids) and request_row.course_id <> v_course_id
  ) then
    raise sqlstate 'PT400' using message = 'request_course_mismatch';
  end if;

  if v_membership_verification = 'external_membership'
    and exists (
    select 1
    from private.course_access_requests as request_row
    where request_row.course_id = v_course_id
      and request_row.status = 'pending'
      and (p_request_ids is null or request_row.id = any (p_request_ids))
      and not exists (
        select 1 from private.profile_identifiers as identifier
        where identifier.profile_id = request_row.requester_profile_id
          and identifier.kind = 'external_user_id'
          and identifier.issuer = v_provider_issuer
          and identifier.revoked_at is null
      )
  ) then
    raise sqlstate 'PT403' using message = 'external_identity_not_provisioned';
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
  select coalesce(array_agg(changed.id), '{}'::uuid[])
  into v_changed_request_ids
  from changed;

  v_count := cardinality(v_changed_request_ids);

  if v_membership_verification = 'approval_only' then
    foreach v_request_id in array v_changed_request_ids loop
      perform private.activate_course_membership_from_request(
        v_request_id,
        'Course access request approved by owner'
      );
    end loop;
  else
    insert into private.external_course_access (course_id, profile_id, access_request_id, external_user_id, state)
    select request_row.course_id,
           request_row.requester_profile_id,
           request_row.id,
           identifier.normalized_value,
           'not_started'
    from private.course_access_requests as request_row
    join private.profile_identifiers as identifier
      on identifier.profile_id = request_row.requester_profile_id
     and identifier.kind = 'external_user_id'
     and identifier.issuer = v_provider_issuer
     and identifier.revoked_at is null
    where request_row.id = any (v_changed_request_ids)
    on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;
  end if;

  return v_count;
end
$function$;

CREATE OR REPLACE FUNCTION public.request_course_access (
  p_offering_key text,
  p_reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_enrollment_mode text;
  v_membership_verification private.course_membership_verification;
  v_provider_issuer text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id,
         course.enrollment_mode::text,
         course.membership_verification,
         organization.provider_issuer
  into v_course_id, v_enrollment_mode, v_membership_verification, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published'
  for update of course;

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
      'state', case
        when v_request.status = 'approved'
          and v_membership_verification = 'external_membership'
          then 'awaiting_external_access'
        when v_request.status = 'approved' then 'active'
        else 'pending'
      end,
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
    and (
      v_membership_verification = 'approval_only'
      or exists (
        select 1
        from private.profile_identifiers as identifier
        where identifier.profile_id = v_profile_id
          and identifier.kind = 'external_user_id'
          and identifier.issuer = v_provider_issuer
          and identifier.revoked_at is null
      )
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
    case when v_auto_approved then 'approved'::private.course_access_request_status
         else 'pending'::private.course_access_request_status end,
    case when v_auto_approved then 'allowlist' else 'owner' end,
    case when v_auto_approved then clock_timestamp() else null end
  )
  returning * into v_request;

  if v_auto_approved then
    if v_membership_verification = 'approval_only' then
      perform private.activate_course_membership_from_request(
        v_request.id,
        'Course access request approved from allowlist'
      );

      return jsonb_build_object(
        'state', 'active',
        'offering_key', p_offering_key,
        'request_id', v_request.id
      );
    end if;

    insert into private.external_course_access (
      course_id, profile_id, access_request_id, external_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      identifier.normalized_value,
      'not_started'
    from private.profile_identifiers as identifier
    where identifier.profile_id = v_profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = v_provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;

    return jsonb_build_object(
      'state', 'awaiting_external_access',
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

CREATE OR REPLACE FUNCTION public.request_my_course_repository (
  p_offering_key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_access_request_id uuid;
  v_course_definition_key text;
  v_external_group_id text;
  v_external_group_handle text;
begin
  select
    course.id,
    course.course_definition_key,
    request_row.id,
    organization.external_group_id,
    organization.external_group_handle
  into
    v_course_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.course_access_requests as request_row
    on request_row.course_id = course.id
   and request_row.requester_profile_id = v_profile_id
   and request_row.id = membership.created_from_access_request_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published'
    and (
      course.membership_verification = 'approval_only'
      or exists (
        select 1
        from private.external_course_access as access_row
        where access_row.course_id = course.id
          and access_row.profile_id = v_profile_id
          and access_row.state = 'active'
          and access_row.external_group_id = organization.external_group_id
          and access_row.external_group_handle = organization.external_group_handle
      )
    )
  for update of course;

  if v_course_id is null then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  insert into private.course_repository_provisioning (
    course_id,
    profile_id,
    course_definition_key,
    access_request_id,
    external_group_id,
    external_group_handle
  ) values (
    v_course_id,
    v_profile_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

ALTER TABLE "private"."course_definition_external_groups"
  ADD CONSTRAINT "course_definition_external_groups_repository_target_unique" UNIQUE (course_definition_key, external_group_id, external_group_handle);

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_access_request_fkey" FOREIGN KEY (access_request_id, course_id, profile_id)
    REFERENCES private.course_access_requests(id, course_id, requester_profile_id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_repository_target_fkey" FOREIGN KEY (course_definition_key, external_group_id, external_group_handle)
    REFERENCES private.course_definition_external_groups(course_definition_key, external_group_id, external_group_handle) ON DELETE RESTRICT;

ALTER TABLE "public"."courses"
  ADD CONSTRAINT "courses_id_definition_key_unique" UNIQUE (id, course_definition_key);

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_course_definition_fkey" FOREIGN KEY (course_id, course_definition_key) REFERENCES public.courses(id, course_definition_key)
    ON DELETE RESTRICT;

COMMENT ON COLUMN "private"."course_definition_external_groups"."external_group_id" IS 'Stable provider group ID used for external membership verification when configured; the handle is only a display snapshot.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."provider_kind" IS 'Provider adapter key, currently github; it selects the external integration used for invitations and repositories.';

COMMENT ON COLUMN "public"."courses"."membership_verification" IS 'Post-approval course membership gate: external_membership requires the configured provider group; approval_only relies on first-party identity and request approval.';

REVOKE ALL ON FUNCTION "private"."activate_course_membership_from_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."activate_course_membership_from_request"(uuid, text) TO "ainigma_maintenance";

GRANT USAGE ON TYPE "private"."course_membership_verification" TO "postgres";
