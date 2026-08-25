-- Development-only identities and one operational course offering.
-- These users have no password and cannot authenticate through email login.
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
  (
    '50000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner@local.ainigma',
    '{"provider":"github","providers":["github"]}',
    '{}',
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'learner@local.ainigma',
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

grant ainigma_maintenance to postgres;
set role ainigma_maintenance;

select private.sync_auth_identity('51000000-0000-0000-0000-000000000001');
select private.sync_auth_identity('51000000-0000-0000-0000-000000000002');
select private.create_course_with_initial_owner(
  'security-fundamentals-local',
  'security-fundamentals',
  'SEC-LOCAL',
  current_setting('ainigma_seed.owner_profile_id')::uuid
);

reset role;

select set_config(
  'ainigma_seed.course_id',
  (select id::text from public.courses where course_key = 'security-fundamentals-local'),
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

reset role;
revoke ainigma_maintenance from postgres;
