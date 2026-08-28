set local check_function_bodies = off;

drop function "public"."get_my_profile"();

drop function "public"."list_my_courses"();

drop function "public"."update_my_profile"(text);

create or replace function private.list_github_course_access_to_reconcile()
  returns table (
    course_id                         uuid,
    profile_id                        uuid,
    access_request_id                 uuid,
    offering_key                      text,
    expected_github_org_id            bigint,
    expected_github_org_slug          text,
    github_user_id                    text,
    github_username                   text,
    github_organization_invitation_id bigint,
    github_email                      text,
    invitation_method                 text,
    invitation_target                 text,
    state                             text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select access_row.course_id,
     access_row.profile_id,
     access_row.access_request_id,
     course.offering_key,
     organization.github_org_id,
     organization.github_org_slug,
     access_row.github_user_id,
     access_row.github_username,
     access_row.github_organization_invitation_id,
     email.normalized_value,
     access_row.invitation_method,
     access_row.invitation_target,
     access_row.state
    from ((((private.github_course_access access_row
      JOIN private.course_access_requests request_row
        on (((request_row.id = access_row.access_request_id) AND (request_row.course_id = access_row.course_id) AND (request_row.requester_profile_id = access_row.profile_id))))
      JOIN public.courses course on ((course.id = access_row.course_id)))
      JOIN private.course_definition_github_organizations organization on ((organization.course_definition_key = course.course_definition_key)))
      LEFT JOIN LATERAL ( select identifier.normalized_value
            from private.profile_identifiers identifier
           where
             ((identifier.profile_id = access_row.profile_id) AND (identifier.kind = 'email'::text) AND (identifier.issuer = 'github.com'::text) AND (identifier.revoked_at is
             null))
           ORDER by identifier.last_verified_at desc
          limit 1) email on (true))
   where ((request_row.status = 'approved'::text) AND (course.status = 'published'::text) AND (access_row.state <> 'revoked'::text));
end;

create or replace function private.report_identity_anomalies()
  returns table (
    anomaly          text,
    profile_id       uuid,
    auth_user_id     uuid,
    auth_identity_id uuid,
    detail           text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select 'orphan_profile'::text
  AS text,
     profile.id,
     NULL::uuid AS uuid,
     NULL::uuid AS uuid,
     'profile has no Auth user link'::text AS text
    FROM public.profiles profile
   WHERE (NOT (EXISTS ( SELECT 1
            FROM private.auth_user_links link
           WHERE (link.profile_id = profile.id))))
 UNION ALL
  SELECT 'unlinked_auth_identity'::text AS text,
     NULL::uuid AS uuid,
     identity_row.user_id,
     identity_row.id,
     'Auth identity user has no application profile link'::text AS text
    FROM private.auth_identities identity_row
   WHERE (NOT (EXISTS ( SELECT 1
            FROM private.auth_user_links link
           WHERE (link.auth_user_id = identity_row.user_id))));
END;

create or replace function private.request_auth_user_id()
  returns uuid
  language sql
  stable
  set search_path to ''
BEGIN ATOMIC
 select auth.uid()
  AS uid;
END;

create or replace function public.get_my_profile()
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select profile.display_name,
     profile.created_at,
     profile.updated_at
    from public.profiles profile
   where (profile.id = private.current_profile_id());
end;

alter function "public"."get_my_profile"() owner to "ainigma_function_owner";

create or replace function public.list_course_roster (
  p_offering_key text
)
  returns table (
    display_name text,
    role         text,
    status       text,
    created_at   timestamp with time zone,
    suspended_at timestamp with time zone,
    revoked_at   timestamp with time zone
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
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

create or replace function public.list_my_course_access_requests()
  returns table (
    offering_key        text,
    request_id          uuid,
    status              text,
    reason              text,
    requested_at        timestamp with time zone,
    decided_at          timestamp with time zone,
    github_access_state text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select course.offering_key,
     request_row.id,
     request_row.status,
     request_row.reason,
     request_row.requested_at,
     request_row.decided_at,
     access_row.state
    from ((private.course_access_requests request_row
      JOIN public.courses course on ((course.id = request_row.course_id)))
      LEFT JOIN private.github_course_access access_row on ((access_row.access_request_id = request_row.id)))
   where (request_row.requester_profile_id = private.current_profile_id())
   ORDER by request_row.requested_at desc;
end;

create or replace function public.list_my_courses()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select
   jsonb_build_object('courses', COALESCE(( select jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_key', course.course_definition_key,
   'course_definition_release_id',
   course.course_definition_release_id,
   'code',
   course.code,
   'course_status',
   course.status,
   'membership_role',
   membership.role,
   'membership_status',
   membership.status,
   'starts_at',
   course.starts_at,
   'ends_at', course.ends_at, 'external_url', course.external_url, 'created_at', course.created_at, 'updated_at', course.updated_at) ORDER by course.offering_key) as jsonb_agg
            from (public.courses course
              JOIN public.course_memberships membership on ((membership.course_id = course.id)))
           where
             ((membership.profile_id = private.current_profile_id()) AND (membership.status = 'active'::text) AND ((course.status = ANY (ARRAY['published'::text,
             'archived'::text])) or ((course.status = 'draft'::text) AND (membership.role = ANY (ARRAY['owner'::text, 'instructor'::text])))))),
             '[]'::jsonb),
             'inactive_memberships',
             COALESCE(( select jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_release_id', course.course_definition_release_id,
             'course_status',
             course.status,
             'membership_role',
             membership.role,
             'membership_status',
             membership.status,
             'created_at', membership.created_at, 'suspended_at', membership.suspended_at, 'revoked_at', membership.revoked_at) ORDER by course.offering_key) as jsonb_agg
            from (public.courses course
              JOIN public.course_memberships membership on ((membership.course_id = course.id)))
           where
             ((membership.profile_id = private.current_profile_id()) AND (not ((membership.status = 'active'::text) AND ((course.status = ANY (ARRAY['published'::text,
             'archived'::text])) or ((course.status = 'draft'::text) AND (membership.role = ANY (ARRAY['owner'::text, 'instructor'::text])))))))), '[]'::jsonb))
  AS jsonb_build_object;
END;

alter function "public"."list_my_courses"() owner to "ainigma_function_owner";

create or replace function public.update_my_profile (
  p_display_name text
)
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language sql
  security definer
  set search_path to ''
BEGIN ATOMIC
 update public.profiles profile
  set display_name = update_my_profile.p_display_name
   where (profile.id = private.current_profile_id())
   RETURNING profile.display_name,
     profile.created_at,
     profile.updated_at;
end;

alter function "public"."update_my_profile"(text) owner to "ainigma_function_owner";

revoke all on function "public"."get_my_profile"() from public;

revoke all on function "public"."get_my_profile"() from "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "authenticated";

revoke all on function "public"."list_my_courses"() from public;

revoke all on function "public"."list_my_courses"() from "ainigma_function_owner";

grant execute on function "public"."list_my_courses"() to "ainigma_function_owner";

grant execute on function "public"."list_my_courses"() to "authenticated";

revoke all on function "public"."update_my_profile"(text) from public;

revoke all on function "public"."update_my_profile"(text) from "ainigma_function_owner";

grant execute on function "public"."update_my_profile"(text) to "ainigma_function_owner";

grant execute on function "public"."update_my_profile"(text) to "authenticated";
