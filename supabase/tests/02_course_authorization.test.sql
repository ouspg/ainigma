begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(30);

select extensions.has_table('public', 'courses', 'courses table exists');
select extensions.has_table('public', 'course_memberships', 'course membership table exists');
select extensions.has_table('private', 'course_membership_events', 'membership audit table exists');
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles has RLS enabled'
);
select extensions.ok(
  (select relforcerowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles forces RLS for non-bypass owners'
);
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.courses'::regclass),
  'courses has RLS enabled'
);
select extensions.ok(
  (select relforcerowsecurity from pg_class where oid = 'public.courses'::regclass),
  'courses forces RLS for non-bypass owners'
);
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.course_memberships'::regclass),
  'memberships has RLS enabled'
);
select extensions.ok(
  (select relforcerowsecurity from pg_class where oid = 'public.course_memberships'::regclass),
  'memberships forces RLS for non-bypass owners'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  ('30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@example.test', '{}', '{}', clock_timestamp(), clock_timestamp()),
  ('30000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'instructor@example.test', '{}', '{}', clock_timestamp(), clock_timestamp()),
  ('30000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'learner@example.test', '{}', '{}', clock_timestamp(), clock_timestamp()),
  ('30000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'outsider@example.test', '{}', '{}', clock_timestamp(), clock_timestamp());

select set_config(
  'ainigma_test.owner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '30000000-0000-0000-0000-000000000001'),
  true
);
select set_config(
  'ainigma_test.instructor_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '30000000-0000-0000-0000-000000000002'),
  true
);
select set_config(
  'ainigma_test.learner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '30000000-0000-0000-0000-000000000003'),
  true
);
select set_config(
  'ainigma_test.outsider_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '30000000-0000-0000-0000-000000000004'),
  true
);

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.create_course_with_initial_owner(
  'security-fundamentals-2026-test',
  'security-fundamentals',
  'SEC-TEST',
  current_setting('ainigma_test.owner_profile_id')::uuid
);
select private.create_course_with_initial_owner(
  'unrelated-course-2026-test',
  'unrelated-course',
  'OTHER',
  current_setting('ainigma_test.outsider_profile_id')::uuid
);
reset role;

select set_config(
  'ainigma_test.course_id',
  (select id::text from public.courses where course_key = 'security-fundamentals-2026-test'),
  true
);

set role ainigma_maintenance;
select private.add_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.instructor_profile_id')::uuid,
  'instructor',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'test instructor'
);
select private.add_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.learner_profile_id')::uuid,
  'learner',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'test learner'
);
reset role;
revoke ainigma_maintenance from postgres;

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);

select extensions.is(
  (
    select count(*)::bigint
    from public.list_course_roster('security-fundamentals-2026-test')
  ),
  3::bigint,
  'an active owner sees profiles in their own roster only'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  1,
  'an active owner sees their draft course'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'inactive_memberships')),
  0,
  'an active owner has no inactive memberships'
);
select * from public.update_my_profile('Course Owner');

select extensions.is(
  (select display_name from public.get_my_profile()),
  'Course Owner'::text,
  'a user updates their own display name'
);

select extensions.ok(
  to_regprocedure('public.update_my_profile(uuid,text)') is null,
  'the profile RPC has no target profile argument'
);

reset role;
update public.courses
set status = 'published'
where course_key = 'security-fundamentals-2026-test';

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);

select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  1,
  'an active learner sees their published course'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'inactive_memberships')),
  0,
  'an active learner has no inactive memberships'
);
select extensions.is(
  (select count(*)::bigint from public.get_my_profile()),
  1::bigint,
  'a learner receives only their own profile'
);
select * from public.update_my_profile('Course Learner');

select extensions.is(
  (select display_name from public.get_my_profile()),
  'Course Learner'::text,
  'a learner updates their own display name'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000004', true);
select extensions.is(
  (
    select count(*)::bigint
    from jsonb_array_elements(public.list_my_courses()->'courses') as course
    where course->>'course_key' = 'security-fundamentals-2026-test'
  ),
  0::bigint,
  'a member of another course cannot see this course'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
select extensions.is(
  (
    select count(*)::bigint
    from public.list_course_roster('security-fundamentals-2026-test')
  ),
  3::bigint,
  'an active instructor sees their course roster profiles'
);

reset role;
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.transition_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.instructor_profile_id')::uuid,
  'instructor',
  'suspended',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'test suspension'
);
reset role;
revoke ainigma_maintenance from postgres;

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  0,
  'a suspended instructor loses course access'
);
select extensions.is(
  (
    select count(*)::bigint
    from jsonb_array_elements(public.list_my_courses()->'inactive_memberships') as membership
    where membership->>'membership_status' = 'suspended'
  ),
  1::bigint,
  'a suspended instructor sees their inactive membership status'
);
select extensions.throws_ok(
  $$select * from public.list_course_roster('security-fundamentals-2026-test')$$,
  'PT404',
  null,
  'a suspended instructor loses roster profile access'
);

reset role;
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
do $final_owner_guard$
begin
  begin
    perform private.transition_course_membership(
      current_setting('ainigma_test.course_id')::uuid,
      current_setting('ainigma_test.owner_profile_id')::uuid,
      'instructor',
      'active',
      current_setting('ainigma_test.owner_profile_id')::uuid,
      'invalid final-owner demotion'
    );
    perform set_config('ainigma_test.final_owner_guard', 'failed', true);
  exception when check_violation then
    perform set_config('ainigma_test.final_owner_guard', 'blocked', true);
  end;
end
$final_owner_guard$;
reset role;

select extensions.is(
  current_setting('ainigma_test.final_owner_guard', true),
  'blocked'::text,
  'the final active owner cannot be demoted'
);

set role ainigma_maintenance;
select private.add_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.outsider_profile_id')::uuid,
  'owner',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'second test owner'
);
select private.transition_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'instructor',
  'active',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'ownership transfer test'
);
reset role;
revoke ainigma_maintenance from postgres;

select extensions.is(
  (
    select count(*)::bigint
    from public.course_memberships
    where course_id = current_setting('ainigma_test.course_id')::uuid
      and role = 'owner'
      and status = 'active'
  ),
  1::bigint,
  'ownership transfer leaves one active owner'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.course_membership_events
    where course_id = current_setting('ainigma_test.course_id')::uuid
  ),
  6::bigint,
  'membership creation and transitions append audit events'
);
select extensions.throws_ok(
  $$update private.course_membership_events set reason = 'tampered'$$,
  '55000',
  null,
  'membership audit events are immutable'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.courses', 'SELECT'),
  'authenticated users cannot select courses directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.courses', 'UPDATE'),
  'browser users cannot update courses'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.course_memberships', 'UPDATE'),
  'browser users cannot update memberships'
);

select * from extensions.finish();
rollback;
