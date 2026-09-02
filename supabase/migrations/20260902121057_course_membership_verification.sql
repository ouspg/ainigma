SET local check_function_bodies = off;

DROP FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp WITH time zone, text);

CREATE OR REPLACE FUNCTION private.branch_course_offering (
  p_offering_key                 text,
  p_course_definition_release_id uuid,
  p_code                         text,
  p_owner_profile_id             uuid,
  p_starts_at                    timestamp with time zone               DEFAULT NULL::timestamp WITH time zone,
  p_ends_at                      timestamp with time zone               DEFAULT NULL::timestamp WITH time zone,
  p_external_url                 text                                   DEFAULT NULL::text,
  p_membership_verification      private.course_membership_verification DEFAULT 'external_membership'::private.course_membership_verification
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_course_id uuid;
  v_course_definition_key text;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  if not exists (
    select 1 from public.profiles as profile where profile.id = p_owner_profile_id
  ) then
    raise exception using errcode = '23503', message = 'owner_profile_not_found';
  end if;

  insert into public.courses (
    offering_key,
    course_definition_key,
    course_definition_release_id,
    code,
    membership_verification,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_offering_key,
    v_course_definition_key,
    p_course_definition_release_id,
    p_code,
    p_membership_verification,
    p_starts_at,
    p_ends_at,
    p_external_url
  )
  returning id into v_course_id;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (v_course_id, p_owner_profile_id, 'owner', 'active');

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
    v_course_id,
    p_owner_profile_id,
    'created',
    'owner',
    'active',
    p_owner_profile_id,
    'initial course owner'
  );

  return v_course_id;
end
$function$;

ALTER FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp
  WITH time zone, text, private.course_membership_verification) OWNER TO "ainigma_function_owner";

REVOKE ALL
  ON FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, private.course_membership_verification)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, private.course_membership_verification)
  TO "ainigma_maintenance";
