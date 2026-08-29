set local check_function_bodies = off;

create or replace function public.list_available_courses()
  returns table (
    offering_key                 text,
    course_definition_key        text,
    course_definition_release_id uuid,
    code                         text,
    enrollment_mode              text,
    starts_at                    timestamp with time zone,
    ends_at                      timestamp with time zone,
    external_url                 text
  )
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select
    course.offering_key,
    course.course_definition_key,
    course.course_definition_release_id,
    course.code,
    course.enrollment_mode,
    course.starts_at,
    course.ends_at,
    course.external_url
  from public.courses as course
  where course.status = 'published';
$function$;

alter function "public"."list_available_courses"() owner to "ainigma_function_owner";

revoke all on function "public"."list_available_courses"() from public;

revoke all on function "public"."list_available_courses"() from "ainigma_function_owner";

grant execute on function "public"."list_available_courses"() to "ainigma_function_owner";

grant execute on function "public"."list_available_courses"() to "anon", "authenticated";
