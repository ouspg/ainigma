set local check_function_bodies = off;

alter table "public"."profiles"
  alter column "display_name" set not null;

alter table "public"."profiles"
  alter column "display_name" set default 'Learner'::text;

create or replace function private.add_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_role             text,
  p_actor_profile_id uuid,
  p_reason           text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_actor_role text;
begin
  if p_role is null or p_role not in ('instructor', 'learner') then
    if p_role = 'owner' then
      raise exception using errcode = '42501', message = 'course_owner_transfer_required';
    end if;
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (p_role in ('owner', 'instructor') and v_actor_role <> 'owner')
    or (p_role = 'learner' and v_actor_role not in ('owner', 'instructor'))
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (p_course_id, p_profile_id, p_role, 'active');

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'created',
    p_role,
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;

create or replace function private.transfer_course_ownership (
  p_course_id            uuid,
  p_new_owner_profile_id uuid,
  p_actor_profile_id     uuid,
  p_reason               text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_current_owner_profile_id uuid;
  v_target_membership public.course_memberships%rowtype;
begin
  if p_course_id is null or p_new_owner_profile_id is null or p_actor_profile_id is null then
    raise exception using errcode = '22004', message = 'course_ownership_transfer_arguments_required';
  end if;

  if p_reason is null or p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_course_membership_reason';
  end if;

  -- All membership mutations lock the course row, so ownership changes are
  -- serialized with staff and learner membership changes.
  perform 1
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.profile_id
  into v_current_owner_profile_id
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.role = 'owner'
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'course_requires_active_owner';
  end if;

  if p_actor_profile_id <> v_current_owner_profile_id then
    raise exception using errcode = '42501', message = 'course_owner_required';
  end if;

  if p_new_owner_profile_id = v_current_owner_profile_id then
    return;
  end if;

  select membership.*
  into v_target_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_new_owner_profile_id
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_owner_target_membership_not_found';
  end if;

  if v_target_membership.role <> 'instructor' then
    raise exception using errcode = '42501', message = 'course_owner_target_must_be_instructor';
  end if;

  -- Demote first so the partial unique index can enforce one active owner
  -- throughout the transaction, then promote the selected instructor.
  update public.course_memberships
  set role = 'instructor'
  where course_id = p_course_id
    and profile_id = v_current_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_current_owner_profile_id,
    'transitioned',
    'owner',
    'active',
    'instructor',
    'active',
    p_actor_profile_id,
    p_reason
  );

  update public.course_memberships
  set role = 'owner'
  where course_id = p_course_id
    and profile_id = p_new_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_target_membership.profile_id,
    'transitioned',
    v_target_membership.role,
    v_target_membership.status,
    'owner',
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;

-- pg-delta cannot represent the temporary schema CREATE privilege required
-- when transferring ownership of a newly created security-definer function.
grant create on schema "private" to "ainigma_function_owner";
alter function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) owner to "ainigma_function_owner";
revoke create on schema "private" from "ainigma_function_owner";

create or replace function private.transition_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_new_role         text,
  p_new_status       text,
  p_actor_profile_id uuid,
  p_reason           text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_membership public.course_memberships%rowtype;
  v_actor_role text;
  v_active_owner_count integer;
begin
  if p_new_role is null or p_new_role not in ('owner', 'instructor', 'learner') then
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  if p_new_role = 'owner' then
    raise exception using errcode = '42501', message = 'course_owner_transfer_required';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (
      p_new_role in ('owner', 'instructor')
      and v_actor_role <> 'owner'
    )
    or (
      p_new_role = 'learner'
      and v_actor_role not in ('owner', 'instructor')
    )
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  select membership.*
  into v_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_membership_not_found';
  end if;

  if v_actor_role = 'instructor' and v_membership.role <> 'learner' then
    raise exception using errcode = '42501', message = 'course_staff_admin_required';
  end if;

  if v_membership.role = p_new_role and v_membership.status = p_new_status then
    return;
  end if;

  if v_membership.role = 'owner'
    and v_membership.status = 'active'
    and (p_new_role <> 'owner' or p_new_status <> 'active')
  then
    select count(*)
    into v_active_owner_count
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.role = 'owner'
      and membership.status = 'active';

    if v_active_owner_count <= 1 then
      raise exception using errcode = '23514', message = 'course_requires_active_owner';
    end if;
  end if;

  update public.course_memberships
  set role = p_new_role,
      status = p_new_status,
      suspended_at = case when p_new_status = 'suspended' then clock_timestamp() else null end,
      revoked_at = case when p_new_status = 'revoked' then clock_timestamp() else null end
  where course_id = p_course_id
    and profile_id = p_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'transitioned',
    v_membership.role,
    v_membership.status,
    p_new_role,
    p_new_status,
    p_actor_profile_id,
    p_reason
  );
end
$function$;

create or replace function public.list_course_access_requests (
  p_course_key           text,
  p_status               text default 'pending'::text,
  p_authorization_filter text default null::text
)
  returns table (
    request_id           uuid,
    course_key           text,
    display_name         text,
    github_username      text,
    verified_email       text,
    reason               text,
    status               text,
    authorization_status text,
    requested_at         timestamp with time zone,
    decided_at           timestamp with time zone,
    github_access_state  text
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
begin
  select course.id into v_course_id
  from public.courses as course
  where course.course_key = p_course_key;

  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    request_row.id,
    course.course_key,
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

alter table "public"."course_memberships"
  add constraint "course_memberships_owner_status_check" check (((role <> 'owner'::text) OR (status = 'active'::text)));

create unique index course_memberships_one_active_owner_uidx on public.course_memberships using btree (course_id)
  where ((role = 'owner'::text) AND (status = 'active'::text));

revoke all on function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) from public;

grant execute on function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) to "ainigma_maintenance";
