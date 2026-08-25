begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(17);

select extensions.has_table('private', 'course_access_requests', 'access request table exists');
select extensions.has_table('private', 'course_roster_allowlist', 'roster allowlist table exists');
select extensions.has_table('private', 'github_course_access', 'GitHub access table exists');
select extensions.ok(
  not has_table_privilege('authenticated', 'private.course_access_requests', 'SELECT'),
  'browser users cannot select access requests directly'
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
values (
  '70000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'requester@example.test',
  '{}',
  '{}',
  clock_timestamp(),
  clock_timestamp()
);

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  created_at,
  updated_at
)
values (
  '71000000-0000-0000-0000-000000000001',
  '97000001',
  '70000000-0000-0000-0000-000000000001',
  '{"sub":"97000001","user_name":"requester-test","email":"requester@university.example","email_verified":true}',
  'github',
  clock_timestamp(),
  clock_timestamp()
);

select set_config(
  'ainigma_access_test.requester_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '70000000-0000-0000-0000-000000000001'),
  true
);
select set_config(
  'ainigma_access_test.owner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '50000000-0000-0000-0000-000000000001'),
  true
);

-- Create a separate published course owned by the seeded owner.
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.sync_auth_identity('71000000-0000-0000-0000-000000000001');
select private.create_course_with_initial_owner(
  'access-gate-course-test',
  'access-gate-course',
  'ACCESS-TEST',
  current_setting('ainigma_access_test.owner_profile_id')::uuid
);
reset role;
update public.courses
set status = 'published'
where course_key = 'access-gate-course-test';
select set_config(
  'ainigma_access_test.course_id',
  (select id::text from public.courses where course_key = 'access-gate-course-test'),
  true
);

set role ainigma_maintenance;
select private.create_course_with_initial_owner(
  'access-gate-auto-course-test',
  'access-gate-auto-course',
  'ACCESS-AUTO-TEST',
  current_setting('ainigma_access_test.owner_profile_id')::uuid
);
reset role;
update public.courses
set status = 'published', enrollment_mode = 'allowlist_auto'
where course_key = 'access-gate-auto-course-test';
select set_config(
  'ainigma_access_test.auto_course_id',
  (select id::text from public.courses where course_key = 'access-gate-auto-course-test'),
  true
);

-- A trusted external roster match is useful for the owner filter, but grants nothing.
set role ainigma_maintenance;
insert into private.course_roster_allowlist (
  course_id,
  identifier_kind,
  identifier_issuer,
  identifier_scheme_version,
  normalized_identifier_value,
  source
)
values (
  current_setting('ainigma_access_test.course_id')::uuid,
  'github_user_id',
  'github.com',
  1,
  '97000001',
  'test roster'
), (
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  'github_user_id',
  'github.com',
  1,
  '97000001',
  'test auto roster'
);
reset role;
revoke ainigma_maintenance from postgres;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

select extensions.is(
  (select public.request_course_access('access-gate-course-test', 'I am enrolled in the university course.')->>'state'),
  'pending',
  'a learner can submit a request with a reason'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  0,
  'a requester cannot access course content before approval'
);
select extensions.is(
  (select count(*)::bigint from public.list_my_course_access_requests() where status = 'pending'),
  1::bigint,
  'the learner sees their pending request'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);

select extensions.is(
  (select count(*)::bigint
   from public.list_course_access_requests('access-gate-course-test', 'pending', 'preauthorized')),
  1::bigint,
  'the owner can filter the queue by trusted roster authorization'
);
select extensions.is(
  (select public.approve_course_access_requests('access-gate-course-test')),
  1,
  'the owner can approve all pending requests'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select extensions.is(
  (select github_access_state
   from public.list_my_course_access_requests()
   limit 1),
  'not_started'::text,
  'approval starts external GitHub access provisioning'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  0,
  'approval alone does not grant course access'
);

reset role;
grant ainigma_maintenance to postgres;
select extensions.throws_ok(
  $$select private.confirm_github_course_access(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    88000001,
    'access-gate-course-test-org',
    '99999999'
  )$$,
  '42501',
  'github_identity_mismatch',
  'a mismatched GitHub identity cannot activate course access'
);
set role ainigma_maintenance;
select private.confirm_github_course_access(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  88000001,
  'access-gate-course-test-org',
  '97000001'
);
reset role;
revoke ainigma_maintenance from postgres;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  1,
  'confirmed GitHub organization membership activates course access'
);
select extensions.is(
  (select (public.request_course_access('access-gate-course-test', null)->>'state')),
  'active',
  'a repeated request returns the existing active course'
);
select extensions.is(
  (select (public.request_course_access('access-gate-auto-course-test', null)->>'state')),
  'awaiting_github_access',
  'allowlist_auto skips owner approval but still waits for GitHub access'
);
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  1,
  'automatic approval alone does not grant the second course'
);

reset role;
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.confirm_github_course_access(
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  88000002,
  'access-gate-auto-course-test-org',
  '97000001'
);
reset role;
revoke ainigma_maintenance from postgres;
set local role authenticated;
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  2,
  'GitHub confirmation activates the automatically approved course'
);

select extensions.finish();
rollback;
