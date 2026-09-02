SET local check_function_bodies = off;

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

  if p_external_invitation_id is not null
    and v_access.external_invitation_id is distinct from p_external_invitation_id
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
    case when p_external_invitation_id is null
      then 'Existing platform organization membership confirmed'
      else 'Platform organization invitation and membership confirmed'
    end
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
