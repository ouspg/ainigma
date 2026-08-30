begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(47);

select extensions.has_table('public', 'courses', 'courses table exists');
select extensions.has_table(
  'private',
  'course_definition_releases',
  'course definition releases table exists'
);
select extensions.has_table('public', 'course_memberships', 'course membership table exists');
select extensions.has_table('private', 'course_membership_events', 'membership audit table exists');
select extensions.ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.course_memberships'::regclass
      and conname = 'course_memberships_owner_status_check'
  ),
  'owner memberships must remain active'
);
select extensions.ok(
  to_regclass('public.course_memberships_one_active_owner_uidx') is not null,
  'each course has at most one active owner'
);
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
insert into private.course_definition_external_groups (
  course_definition_key,
  external_group_id,
  external_group_handle
)
values
  ('security-fundamentals', '88000001', 'security-test-org'),
  ('unrelated-course', '88000002', 'unrelated-test-org');
set role ainigma_maintenance;
select set_config(
  'ainigma_test.security_release_id',
  private.register_course_definition_release(
    'security-fundamentals',
    '1111111111111111111111111111111111111111',
    '1111111111111111111111111111111111111111111111111111111111111111',
    'test:security-fundamentals:release-1'
  )::text,
  true
);
select set_config(
  'ainigma_test.unrelated_release_id',
  private.register_course_definition_release(
    'unrelated-course',
    '2222222222222222222222222222222222222222',
    '2222222222222222222222222222222222222222222222222222222222222222',
    'test:unrelated-course:release-1'
  )::text,
  true
);
select private.branch_course_offering(
  'security-fundamentals-2026-test',
  current_setting('ainigma_test.security_release_id')::uuid,
  'SEC-TEST',
  current_setting('ainigma_test.owner_profile_id')::uuid
);
select private.branch_course_offering(
  'unrelated-course-2026-test',
  current_setting('ainigma_test.unrelated_release_id')::uuid,
  'OTHER',
  current_setting('ainigma_test.outsider_profile_id')::uuid
);
select private.branch_course_offering(
  'security-fundamentals-2027-test',
  current_setting('ainigma_test.security_release_id')::uuid,
  'SEC-NEXT',
  current_setting('ainigma_test.outsider_profile_id')::uuid
);
reset role;

select extensions.is(
  (
    select count(*)::bigint
    from public.courses
    where course_definition_key = 'security-fundamentals'
  ),
  2::bigint,
  'multiple course offerings may share one authored course definition'
);

update public.courses
set status = 'archived'
where offering_key = 'security-fundamentals-2027-test';

set role ainigma_maintenance;
select set_config(
  'ainigma_test.next_security_release_id',
  private.register_course_definition_release(
    'security-fundamentals',
    '3333333333333333333333333333333333333333',
    '3333333333333333333333333333333333333333333333333333333333333333',
    'test:security-fundamentals:release-2'
  )::text,
  true
);
select set_config(
  'ainigma_test.advanced_offering_count',
  private.advance_open_course_offerings_to_release(
    current_setting('ainigma_test.next_security_release_id')::uuid
  )::text,
  true
);
reset role;

select extensions.is(
  current_setting('ainigma_test.advanced_offering_count')::integer,
  1,
  'the compiler advances only the open offering of a course definition'
);

select extensions.is(
  (
    select course_definition_release_id
    from public.courses
    where offering_key = 'security-fundamentals-2026-test'
  ),
  current_setting('ainigma_test.next_security_release_id')::uuid,
  'an open offering follows the newly published definition release'
);
select extensions.is(
  (
    select course_definition_release_id
    from public.courses
    where offering_key = 'security-fundamentals-2027-test'
  ),
  current_setting('ainigma_test.security_release_id')::uuid,
  'an archived offering retains the release from which it branched'
);

select set_config(
  'ainigma_test.course_id',
  (select id::text from public.courses where offering_key = 'security-fundamentals-2026-test'),
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
where offering_key = 'security-fundamentals-2026-test';

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
    where course->>'offering_key' = 'security-fundamentals-2026-test'
  ),
  0::bigint,
  'a member of another course cannot see this course'
);
select extensions.throws_ok(
  $$select * from public.list_course_roster('security-fundamentals-2026-test')$$,
  'PT404',
  'course_not_found',
  'an unrelated authenticated user cannot inspect a course roster'
);
select extensions.is(
  (
    select count(*)::bigint
    from jsonb_array_elements(public.list_my_courses()->'courses') as course
    where course->>'offering_key' = 'security-fundamentals-2027-test'
      and course->>'course_definition_release_id' =
        current_setting('ainigma_test.security_release_id')
  ),
  1::bigint,
  'a member retains access to an archived offering at its retained release'
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
select extensions.throws_ok(
  $$select count(*) from public.list_course_access_requests('security-fundamentals-2026-test', 'pending', null)$$,
  'PT404',
  'course_not_found',
  'an instructor cannot administer the owner-only access-request queue'
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
do $direct_owner_guard$
begin
  begin
    perform private.add_course_membership(
      current_setting('ainigma_test.course_id')::uuid,
      current_setting('ainigma_test.outsider_profile_id')::uuid,
      'owner',
      current_setting('ainigma_test.owner_profile_id')::uuid,
      'direct owner creation is not allowed'
    );
    perform set_config('ainigma_test.direct_owner_guard', 'failed', true);
  exception when insufficient_privilege then
    perform set_config('ainigma_test.direct_owner_guard', 'blocked', true);
  end;
end
$direct_owner_guard$;
reset role;

select extensions.is(
  current_setting('ainigma_test.direct_owner_guard', true),
  'blocked'::text,
  'owner membership creation requires the ownership transfer function'
);

set role ainigma_maintenance;
select private.transition_course_membership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.instructor_profile_id')::uuid,
  'instructor',
  'active',
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'reactivate instructor for ownership transfer'
);
select private.transfer_course_ownership(
  current_setting('ainigma_test.course_id')::uuid,
  current_setting('ainigma_test.instructor_profile_id')::uuid,
  current_setting('ainigma_test.owner_profile_id')::uuid,
  'test ownership transfer'
);

do $staff_admin_guard$
begin
  begin
    perform private.transition_course_membership(
      current_setting('ainigma_test.course_id')::uuid,
      current_setting('ainigma_test.instructor_profile_id')::uuid,
      'learner',
      'active',
      current_setting('ainigma_test.owner_profile_id')::uuid,
      'instructor cannot administer staff'
    );
    perform set_config('ainigma_test.staff_admin_guard', 'failed', true);
  exception when insufficient_privilege then
    perform set_config('ainigma_test.staff_admin_guard', 'blocked', true);
  end;
end
$staff_admin_guard$;

do $former_owner_guard$
begin
  begin
    perform private.transfer_course_ownership(
      current_setting('ainigma_test.course_id')::uuid,
      current_setting('ainigma_test.owner_profile_id')::uuid,
      current_setting('ainigma_test.owner_profile_id')::uuid,
      'invalid transfer actor'
    );
    perform set_config('ainigma_test.former_owner_guard', 'failed', true);
  exception when insufficient_privilege then
    perform set_config('ainigma_test.former_owner_guard', 'blocked', true);
  end;
end
$former_owner_guard$;

reset role;

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
    select role
    from public.course_memberships
    where course_id = current_setting('ainigma_test.course_id')::uuid
      and profile_id = current_setting('ainigma_test.owner_profile_id')::uuid
  ),
  'instructor'::private.course_membership_role,
  'ownership transfer demotes the previous owner to instructor'
);
select extensions.is(
  (
    select role
    from public.course_memberships
    where course_id = current_setting('ainigma_test.course_id')::uuid
      and profile_id = current_setting('ainigma_test.instructor_profile_id')::uuid
  ),
  'owner'::private.course_membership_role,
  'ownership transfer promotes the selected instructor to owner'
);
select extensions.is(
  (
    select count(*)::bigint
    from private.course_membership_events
    where course_id = current_setting('ainigma_test.course_id')::uuid
  ),
  7::bigint,
  'membership creation, reactivation, and transfer append audit events'
);

select extensions.is(
  current_setting('ainigma_test.staff_admin_guard', true),
  'blocked'::text,
  'an instructor cannot administer staff memberships'
);

select extensions.is(
  current_setting('ainigma_test.former_owner_guard', true),
  'blocked'::text,
  'the former owner cannot transfer ownership after demotion'
);

select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'private.transfer_course_ownership(uuid, uuid, uuid, text)',
    'execute'
  ),
  'ownership transfer is not exposed to browser roles'
);

revoke ainigma_maintenance from postgres;
select extensions.throws_ok(
  $$update private.course_membership_events set reason = 'tampered'$$,
  '55000',
  null,
  'membership audit events are immutable'
);
select extensions.throws_ok(
  $$update private.course_definition_releases set artifact_ref = 'tampered'$$,
  '55000',
  null,
  'course definition releases are immutable'
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
