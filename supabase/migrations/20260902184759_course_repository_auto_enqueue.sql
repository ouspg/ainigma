SET local check_function_bodies = off;

ALTER TABLE "private"."external_course_access"
  DROP CONSTRAINT "external_course_access_user_id_check";

ALTER TABLE "private"."external_course_access"
  ALTER COLUMN "external_user_id" DROP NOT NULL;

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
    if v_access.external_user_id is not null
      or v_access.invitation_method <> 'email'
      or p_external_invitation_id is null
    then
      raise exception using errcode = '42501', message = 'external_identity_mismatch';
    end if;

    if exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.kind = 'external_user_id'
        and identifier.issuer = v_provider_issuer
        and identifier.scheme_version = 1
        and identifier.normalized_value = p_external_user_id
        and identifier.profile_id <> p_profile_id
        and identifier.revoked_at is null
    ) or exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.profile_id = p_profile_id
        and identifier.kind = 'external_user_id'
        and identifier.issuer = v_provider_issuer
        and identifier.scheme_version = 1
        and identifier.normalized_value <> p_external_user_id
        and identifier.revoked_at is null
    ) then
      update private.external_course_access
      set state = 'failed',
          last_checked_at = clock_timestamp(),
          failure_code = 'external_identity_conflict'
      where course_id = p_course_id and profile_id = p_profile_id;
      return;
    end if;

    -- Email invitations may discover the provider identity only after
    -- acceptance. The trusted worker has already matched this accepted
    -- invitation ID to p_external_user_id.
    perform private.upsert_verified_identifier(
      p_profile_id,
      'external_user_id',
      v_provider_issuer,
      1,
      p_external_user_id,
      clock_timestamp(),
      null,
      null
    );
  end if;

  update private.profile_identifiers
  set revoked_at = clock_timestamp(),
      last_verified_at = clock_timestamp()
  where profile_id = p_profile_id
    and kind = 'external_user_handle'
    and issuer = v_provider_issuer
    and scheme_version = 1
    and normalized_value <> p_external_user_handle
    and revoked_at is null;

  perform private.upsert_verified_identifier(
    p_profile_id,
    'external_user_handle',
    v_provider_issuer,
    1,
    p_external_user_handle,
    clock_timestamp(),
    null,
    null
  );

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

CREATE OR REPLACE FUNCTION private.enqueue_course_repository_provisioning (
  p_course_id  uuid,
  p_profile_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_course_definition_key text;
  v_access_request_id uuid;
  v_external_group_id text;
  v_external_group_handle text;
  v_repository_template_owner text;
  v_repository_template_name text;
begin
  select
    course.course_definition_key,
    request_row.id,
    organization.external_group_id,
    organization.external_group_handle,
    organization.repository_template_owner,
    organization.repository_template_name
  into
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle,
    v_repository_template_owner,
    v_repository_template_name
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = p_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.course_access_requests as request_row
    on request_row.course_id = course.id
   and request_row.requester_profile_id = p_profile_id
   and request_row.id = membership.created_from_access_request_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
    and (
      course.membership_verification = 'approval_only'
      or exists (
        select 1
        from private.external_course_access as access_row
        where access_row.course_id = course.id
          and access_row.profile_id = p_profile_id
          and access_row.state = 'active'
          and access_row.external_group_id = organization.external_group_id
          and access_row.external_group_handle = organization.external_group_handle
      )
    )
  for update of course;

  if v_access_request_id is null then
    return false;
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
    p_course_id,
    p_profile_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle,
    v_repository_template_owner,
    v_repository_template_name
  )
  on conflict (course_id, profile_id) do nothing;

  return true;
end
$function$;

ALTER FUNCTION "private"."enqueue_course_repository_provisioning"(uuid, uuid) OWNER TO "ainigma_function_owner";

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
    insert into private.external_course_access (
      course_id,
      profile_id,
      access_request_id,
      external_user_id,
      invitation_method,
      invitation_target,
      state
    )
    select request_row.course_id,
           request_row.requester_profile_id,
           request_row.id,
           identifier.normalized_value,
           case when identifier.normalized_value is null
             then 'email'::private.external_invitation_method
             else 'external_user_id'::private.external_invitation_method
           end,
           email.normalized_value,
           'not_started'
    from private.course_access_requests as request_row
    left join lateral (
      select private.unique_active_profile_identifier(
        request_row.requester_profile_id,
        'external_user_id',
        v_provider_issuer
      ) as normalized_value
    ) as identifier on true
    left join lateral (
      select private.unique_active_profile_identifier(
        request_row.requester_profile_id,
        'email',
        null
      ) as normalized_value
    ) as email on true
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
      course_id,
      profile_id,
      access_request_id,
      external_user_id,
      invitation_method,
      invitation_target,
      state
    )
    values (
      v_course_id,
      v_profile_id,
      v_request.id,
      private.unique_active_profile_identifier(v_profile_id, 'external_user_id', v_provider_issuer),
      case when private.unique_active_profile_identifier(v_profile_id, 'external_user_id', v_provider_issuer) is null
        then 'email'::private.external_invitation_method
        else 'external_user_id'::private.external_invitation_method
      end,
      private.unique_active_profile_identifier(v_profile_id, 'email', null),
      'not_started'
    );

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
begin
  select course.id
  into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key
  for update;

  if v_course_id is null then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  if not private.enqueue_course_repository_provisioning(v_course_id, v_profile_id) then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_identity_shape_check" CHECK (((external_user_id IS
    NOT NULL) OR ((invitation_method = 'email'::private.external_invitation_method) AND (state <> 'active'::private.external_course_access_state))));

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_user_id_check"
    CHECK (((external_user_id IS NULL) OR ((external_user_id = btrim(external_user_id)) AND ((char_length(external_user_id) >= 1) AND (char_length(external_user_id) <= 255)))));

COMMENT ON COLUMN "private"."external_course_access"."external_user_id" IS 'Stable external provider account ID. It is bound after an email invitation is accepted and is the identity key thereafter.';

REVOKE ALL ON FUNCTION "private"."enqueue_course_repository_provisioning"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."enqueue_course_repository_provisioning"(uuid, uuid) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";
