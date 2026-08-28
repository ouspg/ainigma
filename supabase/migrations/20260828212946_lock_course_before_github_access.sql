set local check_function_bodies = off;

create or replace function private.confirm_github_course_access (
  p_course_id                         uuid,
  p_profile_id                        uuid,
  p_github_org_id                     bigint,
  p_github_org_slug                   text,
  p_github_organization_invitation_id bigint,
  p_github_user_id                    text,
  p_github_username                   text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
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
