SET local check_function_bodies = off;

DROP FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text);

ALTER TABLE "private"."course_definition_external_groups"
  ADD COLUMN "repository_template_owner" text NOT NULL;

ALTER TABLE "private"."course_definition_external_groups"
  ADD COLUMN "repository_template_name" text NOT NULL;

ALTER TABLE "private"."course_repository_provisioning"
  ADD COLUMN "repository_template_owner" text NOT NULL;

ALTER TABLE "private"."course_repository_provisioning"
  ADD COLUMN "repository_template_name" text NOT NULL;

CREATE OR REPLACE FUNCTION private.claim_course_repository_provisioning (
  p_limit         integer DEFAULT 25,
  p_course_id     uuid    DEFAULT NULL::uuid,
  p_profile_id    uuid    DEFAULT NULL::uuid,
  p_provider_kind text    DEFAULT NULL::text
)
  RETURNS TABLE (
    course_id                 uuid,
    profile_id                uuid,
    access_request_id         uuid,
    offering_key              text,
    provider_kind             text,
    provider_issuer           text,
    external_group_id         text,
    external_group_handle     text,
    repository_template_owner text,
    repository_template_name  text,
    repository_name           text,
    external_repository_id    text,
    external_repository_url   text,
    external_user_handle      text,
    external_user_id          text,
    lease_token               uuid,
    attempt_count             integer
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
      organization.provider_issuer,
      repository.external_group_id,
      repository.external_group_handle,
      repository.repository_template_owner,
      repository.repository_template_name,
      repository.external_repository_id,
      repository.external_repository_url,
      resolved_identity.external_user_id,
      resolved_identity.external_user_handle,
      case
        when resolved_identity.external_user_handle is null then null
        when char_length('submissions-' || course.offering_key || '-' || resolved_identity.external_user_handle) <= 100
          then 'submissions-' || course.offering_key || '-' || resolved_identity.external_user_handle
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || resolved_identity.external_user_handle), 8) || '-' ||
          left(resolved_identity.external_user_handle, 20)
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
     and access_row.access_request_id = repository.access_request_id
     and access_row.external_group_id = repository.external_group_id
     and access_row.external_group_handle = repository.external_group_handle
    left join lateral (
      select
        -- The membership mode is the source-of-truth boundary. An external
        -- membership snapshot must not override a first-party profile fact,
        -- and an unexpected stale access row must not override approval-only
        -- provisioning.
        case
          when course.membership_verification = 'external_membership'
            then access_row.external_user_id
          when course.membership_verification = 'approval_only'
            then private.unique_active_profile_identifier(
              repository.profile_id,
              'external_user_id',
              organization.provider_issuer
            )
          else null
        end as external_user_id,
        case
          when course.membership_verification = 'external_membership'
            then access_row.external_user_handle
          when course.membership_verification = 'approval_only'
            then private.unique_active_profile_identifier(
              repository.profile_id,
              'external_user_handle',
              organization.provider_issuer
            )
          else null
        end as external_user_handle
    ) as resolved_identity on true
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
      and resolved_identity.external_user_id is not null
      and resolved_identity.external_user_handle is not null
      and (p_course_id is null or repository.course_id = p_course_id)
      and (p_profile_id is null or repository.profile_id = p_profile_id)
      and (p_provider_kind is null or organization.provider_kind = p_provider_kind)
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
    organization.provider_issuer,
    claimed.external_group_id,
    claimed.external_group_handle,
    claimed.repository_template_owner,
    claimed.repository_template_name,
    claimed.repository_name,
    claimed.external_repository_id,
    claimed.external_repository_url,
    resolved_identity.external_user_handle,
    resolved_identity.external_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  left join private.external_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
   and access_row.access_request_id = claimed.access_request_id
   and access_row.external_group_id = claimed.external_group_id
   and access_row.external_group_handle = claimed.external_group_handle
  left join lateral (
    select
      case
        when course.membership_verification = 'external_membership'
          then access_row.external_user_id
        when course.membership_verification = 'approval_only'
          then private.unique_active_profile_identifier(
            claimed.profile_id,
            'external_user_id',
            organization.provider_issuer
          )
        else null
      end as external_user_id,
      case
        when course.membership_verification = 'external_membership'
          then access_row.external_user_handle
        when course.membership_verification = 'approval_only'
          then private.unique_active_profile_identifier(
            claimed.profile_id,
            'external_user_handle',
            organization.provider_issuer
          )
        else null
      end as external_user_handle
  ) as resolved_identity on true
  ;
end
$function$;

ALTER FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) OWNER TO "ainigma_function_owner";

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
  v_repository_template_owner text;
  v_repository_template_name text;
begin
  select
    course.id,
    course.course_definition_key,
    request_row.id,
    organization.external_group_id,
    organization.external_group_handle,
    organization.repository_template_owner,
    organization.repository_template_name
  into
    v_course_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle,
    v_repository_template_owner,
    v_repository_template_name
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
    external_group_handle,
    repository_template_owner,
    repository_template_name
  ) values (
    v_course_id,
    v_profile_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle,
    v_repository_template_owner,
    v_repository_template_name
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

ALTER TABLE "private"."course_definition_external_groups"
  ADD CONSTRAINT "course_definition_external_groups_repository_template_name_chec"
    CHECK
    (((repository_template_name = btrim(repository_template_name)) AND ((char_length(repository_template_name) >= 1) AND (char_length(repository_template_name) <= 100)) AND
    (repository_template_name !~ '[[:space:]]'::text)));

ALTER TABLE "private"."course_definition_external_groups"
  ADD CONSTRAINT "course_definition_external_groups_repository_template_owner_che"
    CHECK
    (((repository_template_owner = btrim(repository_template_owner)) AND ((char_length(repository_template_owner) >= 1) AND (char_length(repository_template_owner) <= 255)) AND
    (repository_template_owner !~ '[[:space:]]'::text)));

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_repository_template_name_check"
    CHECK
    (((repository_template_name = btrim(repository_template_name)) AND ((char_length(repository_template_name) >= 1) AND (char_length(repository_template_name) <= 100)) AND
    (repository_template_name !~ '[[:space:]]'::text)));

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_repository_template_owner_check"
    CHECK
    (((repository_template_owner = btrim(repository_template_owner)) AND ((char_length(repository_template_owner) >= 1) AND (char_length(repository_template_owner) <= 255)) AND
    (repository_template_owner !~ '[[:space:]]'::text)));

COMMENT ON COLUMN "private"."course_definition_external_groups"."repository_template_name" IS 'Provider repository name of the public template used for student repositories.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."repository_template_owner" IS 'Provider owner of the public repository template; it may differ from the access group.';

COMMENT ON COLUMN "private"."course_repository_provisioning"."repository_template_name" IS 'Snapshot of the public repository template name used for this job.';

COMMENT ON COLUMN "private"."course_repository_provisioning"."repository_template_owner" IS 'Snapshot of the public repository template owner used for this job; it may differ from the target group.';

REVOKE ALL ON FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";
