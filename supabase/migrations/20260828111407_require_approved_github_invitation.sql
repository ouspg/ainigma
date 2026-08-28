set local check_function_bodies = off;

create or replace function private.record_github_course_access_invitation (
  p_course_id         uuid,
  p_profile_id        uuid,
  p_invitation_method text,
  p_invitation_target text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_target text;
  v_expected_github_org_id bigint;
  v_expected_github_org_slug text;
begin
  if p_invitation_method not in ('email', 'username')
    or p_invitation_target is null
    or p_invitation_target <> btrim(p_invitation_target)
    or char_length(p_invitation_target) not between 1 and 512
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

  select identifier.normalized_value
  into v_expected_target
  from private.profile_identifiers as identifier
  where identifier.profile_id = p_profile_id
    and identifier.kind = case when p_invitation_method = 'email' then 'email' else 'github_username' end
    and identifier.issuer = 'github.com'
    and identifier.revoked_at is null
  order by identifier.last_verified_at desc
  limit 1;

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

  update private.github_course_access
  set github_org_id = v_expected_github_org_id,
      github_org_slug = v_expected_github_org_slug,
      invitation_method = p_invitation_method,
      invitation_target = p_invitation_target,
      state = 'invitation_pending',
      invited_at = coalesce(invited_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;
