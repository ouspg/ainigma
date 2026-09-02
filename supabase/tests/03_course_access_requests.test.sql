begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(60);

select extensions.has_table('private', 'course_access_requests', 'access request table exists');
select extensions.has_table('private', 'course_roster_allowlist', 'roster allowlist table exists');
select extensions.has_table('private', 'external_course_access', 'GitHub access table exists');
select extensions.has_table('private', 'course_repository_provisioning', 'repository provisioning table exists');
select extensions.is(
  (
    select count(*)::integer
    from pg_proc as function_row
    join pg_language as language_row on language_row.oid = function_row.prolang
    where function_row.oid = any (array[
      'private.list_external_course_access_to_reconcile()'::regprocedure,
      'public.list_my_courses()'::regprocedure,
      'public.list_my_course_access_requests()'::regprocedure
    ])
      and language_row.lanname = 'sql'
      and function_row.prosqlbody is not null
  ),
  3,
  'pure course functions use parsed SQL-standard bodies'
);
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
insert into private.course_definition_external_groups (
  course_definition_key,
  provider_kind,
  provider_issuer,
  external_group_id,
  external_group_handle
)
values
  ('access-gate-course', 'github', 'github', '88000001', 'access-gate-course-test-org'),
  ('access-gate-auto-course', 'github', 'github', '88000002', 'access-gate-auto-course-test-org');
insert into private.course_definition_external_email_domains (
  course_definition_key,
  domain_suffix
)
values
  ('access-gate-course', 'student.oulu.fi'),
  ('access-gate-auto-course', 'student.oulu.fi');
set role ainigma_maintenance;
select private.sync_auth_identity('71000000-0000-0000-0000-000000000001');
select private.branch_course_offering(
  'access-gate-course-test',
  private.register_course_definition_release(
    'access-gate-course',
    '4444444444444444444444444444444444444444',
    '4444444444444444444444444444444444444444444444444444444444444444',
    'test:access-gate-course:release-1'
  ),
  'ACCESS-TEST',
  current_setting('ainigma_access_test.owner_profile_id')::uuid
);
reset role;
update public.courses
set status = 'published'
where offering_key = 'access-gate-course-test';
select set_config(
  'ainigma_access_test.course_id',
  (select id::text from public.courses where offering_key = 'access-gate-course-test'),
  true
);

set role ainigma_maintenance;
select private.branch_course_offering(
  'access-gate-auto-course-test',
  private.register_course_definition_release(
    'access-gate-auto-course',
    '5555555555555555555555555555555555555555',
    '5555555555555555555555555555555555555555555555555555555555555555',
    'test:access-gate-auto-course:release-1'
  ),
  'ACCESS-AUTO-TEST',
  current_setting('ainigma_access_test.owner_profile_id')::uuid
);
reset role;
update public.courses
set status = 'published', enrollment_mode = 'allowlist_auto'
where offering_key = 'access-gate-auto-course-test';
select set_config(
  'ainigma_access_test.auto_course_id',
  (select id::text from public.courses where offering_key = 'access-gate-auto-course-test'),
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
  'external_user_id',
  'github',
  1,
  '97000001',
  'test roster'
), (
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  'external_user_id',
  'github',
  1,
  '97000001',
  'test auto roster'
);
reset role;
revoke ainigma_maintenance from postgres;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

reset role;
set local role anon;
select extensions.is(
  (select count(*)::bigint
   from public.list_available_courses()
   where offering_key = 'access-gate-course-test'),
  1::bigint,
  'anonymous users can discover a published offering through the catalog RPC'
);
reset role;
update public.courses
set status = 'draft'
where offering_key = 'access-gate-auto-course-test';
set local role authenticated;
select extensions.is(
  (select count(*)::bigint
   from public.list_available_courses()
   where offering_key = 'access-gate-course-test'),
  1::bigint,
  'the course catalog includes published offerings'
);
select extensions.is(
  (select count(*)::bigint
   from public.list_available_courses()
   where offering_key = 'access-gate-auto-course-test'),
  0::bigint,
  'the course catalog excludes draft offerings'
);
reset role;
update public.courses
set status = 'archived'
where offering_key = 'access-gate-auto-course-test';
set local role authenticated;
select extensions.is(
  (select count(*)::bigint
   from public.list_available_courses()
   where offering_key = 'access-gate-auto-course-test'),
  0::bigint,
  'the course catalog excludes archived offerings'
);
reset role;
update public.courses
set status = 'published'
where offering_key = 'access-gate-auto-course-test';
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
select extensions.throws_ok(
  $$select count(*) from public.list_course_access_requests('access-gate-course-test', 'pending', 'all')$$,
  'PT404',
  'course_not_found',
  'a learner cannot inspect the staff access-request queue'
);
select extensions.throws_ok(
  $$select public.approve_course_access_requests('access-gate-course-test')$$,
  'PT404',
  'course_not_found',
  'a learner cannot approve access requests'
);
select extensions.throws_ok(
  $$select public.reject_course_access_requests('access-gate-course-test')$$,
  'PT404',
  'course_not_found',
  'a learner cannot reject access requests'
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
  (select external_access_state::text
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
select extensions.throws_ok(
  $$select public.request_my_course_repository('access-gate-course-test')$$,
  'PT403',
  'course_repository_request_not_allowed',
  'repository provisioning cannot be requested before GitHub access is active'
);

reset role;
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    'email',
    'requester@example.com',
    '98000000'
  )$$,
  '22023',
  'email_domain_not_allowed',
  'email invitations reject domains outside the institution'
);
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    'email',
    'requester@notoulu.fi',
    '98000000'
  )$$,
  '22023',
  'email_domain_not_allowed',
  'email invitations reject lookalike domains'
);
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    'email',
    'requester@.oulu.fi',
    '98000003'
  )$$,
  '22023',
  'email_domain_not_allowed',
  'email invitations reject empty subdomains'
);
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    'email',
    'requester@dept..oulu.fi',
    '98000004'
  )$$,
  '22023',
  'email_domain_not_allowed',
  'email invitations reject malformed subdomains'
);
select private.record_external_course_access_invitation(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'email',
  'requester@student.oulu.fi',
  '98000001'
);
select private.record_external_course_access_invitation(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'email',
  'requester@dept.student.oulu.fi',
  '98000002'
);
select private.record_external_course_access_invitation(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'email',
  'requester@student.oulu.fi',
  '98000001'
);
select private.record_external_course_access_invitation(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'email',
  'requester@student.oulu.fi',
  '98000001'
);
reset role;
revoke ainigma_maintenance from postgres;
set local role authenticated;
select extensions.is(
  (select external_access_state::text
   from public.list_my_course_access_requests()
   limit 1),
  'invitation_pending'::text,
  'the trusted integration can record that an invitation is pending'
);
reset role;
grant ainigma_maintenance to postgres;
select extensions.is(
  (select invitation_method::text
   from private.external_course_access
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'email'::text,
  'the invitation method is stored'
);
select extensions.is(
  (select invitation_target
   from private.external_course_access
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'requester@student.oulu.fi'::text,
  'the allowed invitation target is stored'
);
select extensions.is(
  (select external_invitation_id
   from private.external_course_access
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  '98000001'::text,
  'the exact GitHub organization invitation ID is stored'
);
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    '88000001',
    'access-gate-course-test-org',
    '98000001',
    '99999999',
    'requester-test'
  )$$,
  '42501',
  'external_identity_mismatch',
  'a mismatched GitHub identity cannot activate course access'
);
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    '88000002',
    'access-gate-auto-course-test-org',
    '98000001',
    '97000001',
    'requester-test'
  )$$,
  '42501',
  'external_group_mismatch',
  'a GitHub organization configured for another course cannot activate this offering'
);
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    '88000001',
    'access-gate-course-test-org',
    '98000002',
    '97000001',
    'requester-test'
  )$$,
  '42501',
  'external_invitation_mismatch',
  'a different GitHub invitation cannot activate this offering'
);
set role ainigma_maintenance;
select private.confirm_external_course_access(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  '88000001',
  'access-gate-course-test-org',
  '98000001',
  '97000001',
  'requester-test'
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
  (select public.get_my_course_repository('access-gate-course-test')->>'state'),
  'not_requested',
  'course access activation does not automatically request a repository'
);
reset role;
grant ainigma_maintenance to postgres;
select extensions.is(
  (select external_user_handle
   from private.external_course_access
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'requester-test'::text,
  'confirmed membership stores the current GitHub username handle'
);
select extensions.is(
  (select count(*)::bigint
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  0::bigint,
  'GitHub confirmation leaves repository provisioning unrequested'
);
reset role;
revoke ainigma_maintenance from postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select extensions.is(
  (select public.request_my_course_repository('access-gate-course-test')->>'state'),
  'queued'::text,
  'an active learner can explicitly request a repository'
);
select extensions.is(
  (select public.request_my_course_repository('access-gate-course-test')->>'state'),
  'queued'::text,
  'repeating the repository request returns the existing job'
);
reset role;
grant ainigma_maintenance to postgres;
select extensions.is(
  (select state
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'queued'::text,
  'the explicit request queues one repository job for the offering and profile'
);
select extensions.is(
  (select external_group_handle
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'access-gate-course-test-org'::text,
  'repository job stores the configured GitHub organization'
);
set role ainigma_maintenance;
select set_config(
  'ainigma_access_test.repository_lease_token',
  (select lease_token::text
   from private.claim_course_repository_provisioning(
     1,
     current_setting('ainigma_access_test.course_id')::uuid,
     current_setting('ainigma_access_test.requester_profile_id')::uuid
   )),
  true
);
reset role;
select extensions.is(
  (select repository_name
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'submissions-access-gate-course-test-requester-test'::text,
  'repository claim generates the offering and username repository name'
);
set role ainigma_maintenance;
select private.record_course_repository_provisioning_failure(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  current_setting('ainigma_access_test.repository_lease_token')::uuid,
  'repository_create_http_500',
  true
);
reset role;
select extensions.is(
  (select state
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'retry_wait'::text,
  'a retryable repository failure waits with bounded backoff'
);
update private.course_repository_provisioning
set next_attempt_at = clock_timestamp()
where course_id = current_setting('ainigma_access_test.course_id')::uuid
  and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid;
update private.external_course_access
set external_user_handle = 'requester-renamed'
where course_id = current_setting('ainigma_access_test.course_id')::uuid
  and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid;
set role ainigma_maintenance;
select set_config(
  'ainigma_access_test.repository_lease_token',
  (select lease_token::text
   from private.claim_course_repository_provisioning(
     1,
     current_setting('ainigma_access_test.course_id')::uuid,
     current_setting('ainigma_access_test.requester_profile_id')::uuid
   )),
  true
);
reset role;
select extensions.is(
  (select repository_name
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'submissions-access-gate-course-test-requester-test'::text,
  'repository retries preserve the first selected name after a username change'
);
set role ainigma_maintenance;
select private.complete_course_repository_provisioning(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  current_setting('ainigma_access_test.repository_lease_token')::uuid,
  '99000001',
  'submissions-access-gate-course-test-requester-test',
  'https://github.example.test/access-gate-course-test-requester-test'
);
reset role;
select extensions.is(
  (select state
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'ready'::text,
  'repository completion records the ready state'
);
set role ainigma_maintenance;
select private.complete_course_repository_provisioning(
  current_setting('ainigma_access_test.course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  current_setting('ainigma_access_test.repository_lease_token')::uuid,
  '99000001',
  'submissions-access-gate-course-test-requester-test',
  'https://github.example.test/access-gate-course-test-requester-test'
);
reset role;
select extensions.is(
  (select count(*)::bigint
   from private.course_repository_provisioning
   where course_id = current_setting('ainigma_access_test.course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  1::bigint,
  'repeating repository completion does not create a duplicate job'
);
reset role;
revoke ainigma_maintenance from postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select extensions.is(
  (select public.get_my_course_repository('access-gate-course-test')->>'state'),
  'ready'::text,
  'the learner can read the completed repository state'
);
reset role;
grant ainigma_maintenance to postgres;
select extensions.throws_ok(
  $$
    update private.course_repository_provisioning
    set external_group_id = 99999999
    where course_id = current_setting('ainigma_access_test.course_id')::uuid
      and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid
  $$,
  '23503',
  null,
  'a repository job cannot be connected to a different GitHub organization'
);
revoke ainigma_maintenance from postgres;
set local role authenticated;
select extensions.is(
  (select (public.request_course_access('access-gate-auto-course-test', null)->>'state')),
  'awaiting_external_access',
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
select private.record_external_course_access_invitation(
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'external_user_id',
  '97000001',
  '98000002'
);
select private.confirm_external_course_access(
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  '88000002',
  'access-gate-auto-course-test-org',
  '98000002',
  '97000001',
  'requester-test'
);
reset role;
revoke ainigma_maintenance from postgres;
set local role authenticated;
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  2,
  'GitHub confirmation activates the automatically approved course'
);

reset role;
grant ainigma_maintenance to postgres;
set role ainigma_maintenance;
select private.record_external_course_access_check_failure(
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  'external_request_failed'
);
reset role;
select extensions.is(
  (select state
   from private.external_course_access
   where course_id = current_setting('ainigma_access_test.auto_course_id')::uuid
     and profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid),
  'active'::private.external_course_access_state,
  'a transient GitHub check failure preserves confirmed access'
);
set role ainigma_maintenance;
select private.confirm_external_course_access(
  current_setting('ainigma_access_test.auto_course_id')::uuid,
  current_setting('ainigma_access_test.requester_profile_id')::uuid,
  '88000002',
  'access-gate-auto-course-test-org',
  '98000002',
  '97000001',
  'requester-test'
);
reset role;
select extensions.is(
  private.record_external_course_access_membership_absence(
    current_setting('ainigma_access_test.auto_course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid
  ),
  false,
  'one missing member snapshot does not revoke offering access'
);
select extensions.is(
  private.record_external_course_access_membership_absence(
    current_setting('ainigma_access_test.auto_course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid
  ),
  false,
  'two consecutive missing snapshots still preserve offering access'
);
select extensions.is(
  private.record_external_course_access_membership_absence(
    current_setting('ainigma_access_test.auto_course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid
  ),
  true,
  'three consecutive missing snapshots revoke offering access'
);
revoke ainigma_maintenance from postgres;
set local role authenticated;
select extensions.is(
  (select jsonb_array_length(public.list_my_courses()->'courses')),
  1,
  'revoked GitHub membership removes local access to that offering'
);
select extensions.is(
  (public.list_my_courses()->'inactive_memberships'->0->>'membership_status'),
  'revoked'::text,
  'revoked GitHub membership records a revoked local membership'
);

reset role;
with mismatched_request as (
  insert into private.course_access_requests (
    course_id,
    requester_profile_id,
    status,
    decision_source,
    decided_at
  )
  values (
    current_setting('ainigma_access_test.auto_course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    'approved',
    'allowlist',
    clock_timestamp()
  )
  returning id
)
select set_config(
  'ainigma_access_test.mismatched_request_id',
  (select id::text from mismatched_request),
  true
);

select extensions.throws_ok(
  $$
    update private.external_course_access as access_row
    set access_request_id = current_setting('ainigma_access_test.mismatched_request_id')::uuid
    where access_row.course_id = current_setting('ainigma_access_test.course_id')::uuid
      and access_row.profile_id = current_setting('ainigma_access_test.requester_profile_id')::uuid
  $$,
  '23503',
  null,
  'GitHub access cannot reference a request for another course'
);

update public.courses
set status = 'archived'
where id = current_setting('ainigma_access_test.course_id')::uuid;
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    current_setting('ainigma_access_test.course_id')::uuid,
    current_setting('ainigma_access_test.requester_profile_id')::uuid,
    '88000001',
    'access-gate-course-test-org',
    '98000001',
    '97000001',
    'requester-renamed'
  )$$,
  '55000',
  'course_offering_not_reconcilable',
  'archived offerings reject late GitHub membership confirmation'
);
select extensions.is(
  (select count(*)::bigint
   from private.list_external_course_access_to_reconcile()
   where course_id = current_setting('ainigma_access_test.course_id')::uuid),
  0::bigint,
  'archived offerings stop GitHub membership reconciliation'
);

select extensions.finish();
rollback;
