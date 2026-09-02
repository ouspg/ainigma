-- @generated from seed.template.sql and dev-personas.json; do not edit manually.
-- Development-only seed. The persona payload is generated from dev-personas.json.
-- Keep this file next to the schema: it is the schema-aware seed adapter.

grant ainigma_maintenance to postgres;

select set_config(
  'ainigma_seed.personas',
  $ainigma_fixture$
[
  {
    "key": "emptyLearner",
    "label": "Empty learner",
    "description": "Signed in with no course membership or access request.",
    "email": "empty-learner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000003",
    "identityId": "51000000-0000-0000-0000-000000000003",
    "providerId": "90000003",
    "profileLabel": "Empty Learner",
    "memberships": []
  },
  {
    "key": "pendingLearner",
    "label": "Pending learner",
    "description": "Has requested access to test course A.",
    "email": "pending-learner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000004",
    "identityId": "51000000-0000-0000-0000-000000000004",
    "providerId": "90000004",
    "profileLabel": "Pending Learner",
    "memberships": [],
    "accessRequests": [
      {
        "offeringKey": "test-course-a-local",
        "reason": "development seed pending request"
      }
    ]
  },
  {
    "key": "memberCourseA",
    "label": "Member · course A",
    "description": "Has active learner access to test course A only.",
    "email": "learner-a@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000002",
    "identityId": "51000000-0000-0000-0000-000000000002",
    "providerId": "90000002",
    "profileLabel": "Ainoa · Course A",
    "memberships": [
      {
        "offeringKey": "test-course-a-local",
        "role": "learner"
      }
    ]
  },
  {
    "key": "memberCourseB",
    "label": "Member · course B",
    "description": "Has active learner access to test course B only.",
    "email": "learner-b@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000006",
    "identityId": "51000000-0000-0000-0000-000000000006",
    "providerId": "90000006",
    "profileLabel": "Ainoa · Course B",
    "memberships": [
      {
        "offeringKey": "test-course-b-local",
        "role": "learner"
      }
    ]
  },
  {
    "key": "memberBothCourses",
    "label": "Member · both courses",
    "description": "Has active learner access to test courses A and B.",
    "email": "learner-both@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000007",
    "identityId": "51000000-0000-0000-0000-000000000007",
    "providerId": "90000007",
    "profileLabel": "Ainoa · Both Courses",
    "memberships": [
      {
        "offeringKey": "test-course-a-local",
        "role": "learner"
      },
      {
        "offeringKey": "test-course-b-local",
        "role": "learner"
      }
    ]
  },
  {
    "key": "instructor",
    "label": "Instructor",
    "description": "Has instructor access to test course A.",
    "email": "instructor@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000005",
    "identityId": "51000000-0000-0000-0000-000000000005",
    "providerId": "90000005",
    "profileLabel": "Course Instructor",
    "memberships": [
      {
        "offeringKey": "test-course-a-local",
        "role": "instructor"
      }
    ]
  },
  {
    "key": "owner",
    "label": "Course owner",
    "description": "Owns the seeded test courses and can review requests.",
    "email": "owner@local.ainigma",
    "userId": "50000000-0000-0000-0000-000000000001",
    "identityId": "51000000-0000-0000-0000-000000000001",
    "providerId": "90000001",
    "profileLabel": "Course Owner",
    "memberships": []
  }
]
$ainigma_fixture$,
  false
);

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
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  (persona ->> 'userId')::uuid,
  'authenticated',
  'authenticated',
  persona ->> 'email',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '{"provider":"github","providers":["github"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as data(persona);

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  created_at,
  updated_at
)
select
  (persona ->> 'identityId')::uuid,
  persona ->> 'providerId',
  (persona ->> 'userId')::uuid,
  jsonb_build_object(
    'sub', persona ->> 'providerId',
    'user_name', 'ainigma-local-' || (persona ->> 'key'),
    'email', persona ->> 'email',
    'email_verified', true
  ),
  'github',
  clock_timestamp(),
  clock_timestamp()
from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as data(persona);

select set_config(
  'ainigma_seed.profile_ids',
  coalesce(
    (
      select jsonb_object_agg(persona ->> 'key', link.profile_id::text)::text
      from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as data(persona)
      join private.auth_user_links as link
        on link.auth_user_id = (persona ->> 'userId')::uuid
    ),
    '{}'::text
  ),
  false
);

update public.profiles as profile
set display_name = persona ->> 'profileLabel'
from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as data(persona)
join private.auth_user_links as link
  on link.auth_user_id = (persona ->> 'userId')::uuid
where profile.id = link.profile_id;

set role ainigma_maintenance;
select private.sync_auth_identity((persona ->> 'identityId')::uuid)
from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as data(persona);
reset role;

insert into private.course_definition_external_groups (
  course_definition_key,
  provider_kind,
  provider_issuer,
  external_group_id,
  external_group_handle,
  repository_template_owner,
  repository_template_name
)
values
  ('test-course-a', 'github', 'github', '88000001', 'ainigma-dev-course-org', 'ainigma-course-templates', 'course-submission-template'),
  ('test-course-b', 'github', 'github', '88000001', 'ainigma-dev-course-org', 'ainigma-course-templates', 'course-submission-template');

insert into private.course_definition_releases (
  id,
  course_definition_key,
  source_commit_sha,
  course_release_digest,
  artifact_ref
)
values
  (
    '60000000-0000-0000-0000-000000000001',
    'test-course-a',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'ainigma-dev:test-course-a:release-1'
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    'test-course-b',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'ainigma-dev:test-course-b:release-1'
  );

select private.branch_course_offering(
  'test-course-a-local',
  '60000000-0000-0000-0000-000000000001',
  'TEST-A',
  (current_setting('ainigma_seed.profile_ids')::jsonb ->> 'owner')::uuid
);
select private.branch_course_offering(
  'test-course-b-local',
  '60000000-0000-0000-0000-000000000002',
  'TEST-B',
  (current_setting('ainigma_seed.profile_ids')::jsonb ->> 'owner')::uuid
);

update public.courses
set status = 'published'
where offering_key in ('test-course-a-local', 'test-course-b-local');

select set_config(
  'ainigma_seed.offering_ids',
  (
    select jsonb_object_agg(replace(offering_key, '-', '_'), id::text)::text
    from public.courses
    where offering_key in ('test-course-a-local', 'test-course-b-local')
  ),
  false
);

set role ainigma_maintenance;

select private.add_course_membership(
  (current_setting('ainigma_seed.offering_ids')::jsonb ->> replace(membership ->> 'offeringKey', '-', '_'))::uuid,
  (current_setting('ainigma_seed.profile_ids')::jsonb ->> (persona ->> 'key'))::uuid,
  (membership ->> 'role')::private.course_membership_role,
  (current_setting('ainigma_seed.profile_ids')::jsonb ->> 'owner')::uuid,
  'development seed ' || (persona ->> 'key')
)
from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as people(persona)
cross join lateral jsonb_array_elements(coalesce(persona -> 'memberships', '[]'::jsonb)) as memberships(membership);

with requests as (
  select
    row_number() over (order by persona ->> 'key', request ->> 'offeringKey') as request_number,
    persona ->> 'key' as persona_key,
    request ->> 'offeringKey' as offering_key,
    request ->> 'reason' as reason
  from jsonb_array_elements(current_setting('ainigma_seed.personas')::jsonb) as people(persona)
  cross join lateral jsonb_array_elements(coalesce(persona -> 'accessRequests', '[]'::jsonb)) as access(request)
)
insert into private.course_access_requests (
  id,
  course_id,
  requester_profile_id,
  reason,
  status,
  decision_source
)
select
  ('52000000-0000-0000-0000-' || lpad(request_number::text, 12, '0'))::uuid,
  (current_setting('ainigma_seed.offering_ids')::jsonb ->> replace(offering_key, '-', '_'))::uuid,
  (current_setting('ainigma_seed.profile_ids')::jsonb ->> persona_key)::uuid,
  reason,
  'pending',
  'owner'
from requests;

reset role;
revoke ainigma_maintenance from postgres;
