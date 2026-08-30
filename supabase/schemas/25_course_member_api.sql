-- Authenticated course discovery, roster, access, and repository self-service RPCs.

-- Published offering metadata is safe to discover before enrollment. This
-- endpoint does not expose membership, repository, or authored content state;
-- the caller still has to request access for the selected offering.
-- Keep this as a SQL function; its quoted body also remains executable when
-- the Supabase CLI generates a migration for a newly created function.
create function public.list_available_courses()
returns table (
  offering_key text,
  course_definition_key text,
  course_definition_release_id uuid,
  code text,
  enrollment_mode text,
  starts_at timestamptz,
  ends_at timestamptz,
  external_url text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    course.offering_key,
    course.course_definition_key,
    course.course_definition_release_id,
    course.code,
    course.enrollment_mode::text,
    course.starts_at,
    course.ends_at,
    course.external_url
  from public.courses as course
  where course.status = 'published';
$function$;

-- Learners see published or archived memberships; draft offerings remain visible only to active staff.
create function public.list_my_courses()
returns jsonb
language sql
stable
security definer
set search_path = ''
begin atomic
  select jsonb_build_object(
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
        where membership.profile_id = private.current_profile_id()
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
        where membership.profile_id = private.current_profile_id()
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
end;

-- Roster access intentionally hides whether an unknown or unauthorized offering exists.
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

-- An access request is offering-specific and may auto-approve only from a currently verified allowlist fact.
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
  v_provider_issuer text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id, course.enrollment_mode::text, organization.provider_issuer
  into v_course_id, v_enrollment_mode, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
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
      'state', case when v_request.status = 'approved' then 'awaiting_external_access' else 'pending' end,
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
        and identifier.kind = 'external_user_id'
        and identifier.issuer = v_provider_issuer
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
    'repository_url', v_repository.external_repository_url,
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
  v_external_group_id text;
  v_external_group_handle text;
begin
  select
    course.id,
    access_row.access_request_id,
    access_row.external_group_id,
    access_row.external_group_handle
  into
    v_course_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.external_course_access as access_row
    on access_row.course_id = course.id
   and access_row.profile_id = v_profile_id
   and access_row.state = 'active'
   and access_row.external_user_handle is not null
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
   and organization.external_group_id = access_row.external_group_id
   and organization.external_group_handle = access_row.external_group_handle
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
    external_group_id,
    external_group_handle
  ) values (
    v_course_id,
    v_profile_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

-- Reading request history never exposes another profile's application or GitHub state.
create function public.list_my_course_access_requests()
returns table (
  offering_key text,
  request_id uuid,
  status text,
  reason text,
  requested_at timestamptz,
  decided_at timestamptz,
  external_access_state text
)
language sql
stable
security definer
set search_path = ''
begin atomic
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
  left join private.external_course_access as access_row
    on access_row.access_request_id = request_row.id
  where request_row.requester_profile_id = private.current_profile_id()
  order by request_row.requested_at desc;
end;
