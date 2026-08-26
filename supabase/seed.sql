-- Development-only identities and one operational course offering.
-- These users have no password and cannot authenticate through product email login. Local web
-- development can use the Auth Admin magic-link bootstrap with the fixed personas below.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  confirmation_token,
  recovery_token,
  email_change_token_current,
  email_change_token_new,
  email_change,
  phone_change_token,
  phone_change,
  reauthentication_token,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '50000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner@local.ainigma',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '50000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'learner@local.ainigma',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '50000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'empty-learner@local.ainigma',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '50000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'pending-learner@local.ainigma',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
    '{"provider":"github","providers":["github"]}',
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
values
  (
    '51000000-0000-0000-0000-000000000001',
    '90000001',
    '50000000-0000-0000-0000-000000000001',
    '{"sub":"90000001","user_name":"ainigma-local-owner","email":"owner@local.ainigma","email_verified":true}',
    'github',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '51000000-0000-0000-0000-000000000002',
    '90000002',
    '50000000-0000-0000-0000-000000000002',
    '{"sub":"90000002","user_name":"ainigma-local-learner","email":"learner@local.ainigma","email_verified":true}',
    'github',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '51000000-0000-0000-0000-000000000003',
    '90000003',
    '50000000-0000-0000-0000-000000000003',
    '{"sub":"90000003","user_name":"ainigma-local-empty-learner","email":"empty-learner@local.ainigma","email_verified":true}',
    'github',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '51000000-0000-0000-0000-000000000004',
    '90000004',
    '50000000-0000-0000-0000-000000000004',
    '{"sub":"90000004","user_name":"ainigma-local-pending-learner","email":"pending-learner@local.ainigma","email_verified":true}',
    'github',
    clock_timestamp(),
    clock_timestamp()
  );

select set_config(
  'ainigma_seed.owner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '50000000-0000-0000-0000-000000000001'),
  false
);
select set_config(
  'ainigma_seed.learner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '50000000-0000-0000-0000-000000000002'),
  false
);
select set_config(
  'ainigma_seed.empty_learner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '50000000-0000-0000-0000-000000000003'),
  false
);
select set_config(
  'ainigma_seed.pending_learner_profile_id',
  (select profile_id::text from private.auth_user_links where auth_user_id = '50000000-0000-0000-0000-000000000004'),
  false
);

update public.profiles
set display_name = case id
  when current_setting('ainigma_seed.owner_profile_id')::uuid then 'Course Owner'
  when current_setting('ainigma_seed.learner_profile_id')::uuid then 'Ainoa Student'
  when current_setting('ainigma_seed.empty_learner_profile_id')::uuid then 'Empty Learner'
  when current_setting('ainigma_seed.pending_learner_profile_id')::uuid then 'Pending Learner'
  else display_name
end
where id in (
  current_setting('ainigma_seed.owner_profile_id')::uuid,
  current_setting('ainigma_seed.learner_profile_id')::uuid,
  current_setting('ainigma_seed.empty_learner_profile_id')::uuid,
  current_setting('ainigma_seed.pending_learner_profile_id')::uuid
);

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;

select private.sync_auth_identity('51000000-0000-0000-0000-000000000001');
select private.sync_auth_identity('51000000-0000-0000-0000-000000000002');
select private.sync_auth_identity('51000000-0000-0000-0000-000000000003');
select private.sync_auth_identity('51000000-0000-0000-0000-000000000004');
select private.create_course_with_initial_owner(
  'test-course-a-local',
  'test-course-a',
  'TEST-A',
  current_setting('ainigma_seed.owner_profile_id')::uuid
);
update public.courses
set status = 'published'
where course_key = 'test-course-a-local';

reset role;

select set_config(
  'ainigma_seed.course_id',
  (select id::text from public.courses where course_key = 'test-course-a-local'),
  false
);

set role ainigma_maintenance;
select private.add_course_membership(
  current_setting('ainigma_seed.course_id')::uuid,
  current_setting('ainigma_seed.learner_profile_id')::uuid,
  'learner',
  current_setting('ainigma_seed.owner_profile_id')::uuid,
  'development seed learner'
);
insert into private.course_access_requests (
  id,
  course_id,
  requester_profile_id,
  reason,
  status,
  decision_source
)
values (
  '52000000-0000-0000-0000-000000000001',
  current_setting('ainigma_seed.course_id')::uuid,
  current_setting('ainigma_seed.pending_learner_profile_id')::uuid,
  'development seed pending request',
  'pending',
  'owner'
);

reset role;
revoke ainigma_maintenance from postgres;
