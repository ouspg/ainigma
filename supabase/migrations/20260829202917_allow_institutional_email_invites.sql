set local check_function_bodies = off;

create or replace function private.record_external_course_access_invitation (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_invitation_method      text,
  p_invitation_target      text,
  p_external_invitation_id text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_email_domain text;
  v_email_domain_enforced boolean;
  v_email_domain_allowed boolean;
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
