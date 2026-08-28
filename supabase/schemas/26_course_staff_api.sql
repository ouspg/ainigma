-- Authenticated course access-request administration RPCs.

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



