-- Disposable real-provider test fixture.
--
-- This seeds the production course-access and repository-provisioning tables.
-- It does not create GitHub members or repositories; those are created by the
-- worker and remain in GitHub when this database is reset.
--
-- Required psql variables:
--   test_offering_key
--   test_organization_id
--   test_organization_handle
--   test_template_owner
--   test_template_repository
--   test_email_domain
--   test_owner_auth_user_id
--   test_emails (newline-separated email addresses)
--
\if :{?test_offering_key}
\else
  \set test_offering_key test-course-a-local
\endif
\if :{?test_organization_id}
\else
  \echo 'test_organization_id is required'
  \quit 3
\endif
\if :{?test_organization_handle}
\else
  \echo 'test_organization_handle is required'
  \quit 3
\endif
\if :{?test_template_owner}
\else
  \echo 'test_template_owner is required'
  \quit 3
\endif
\if :{?test_template_repository}
\else
  \echo 'test_template_repository is required'
  \quit 3
\endif
\if :{?test_email_domain}
\else
  \echo 'test_email_domain is required'
  \quit 3
\endif
\if :{?test_owner_auth_user_id}
\else
  \echo 'test_owner_auth_user_id is required'
  \quit 3
\endif
\if :{?test_emails}
\else
  \set test_emails 'student-01@example.edu'
\endif

select count(*)::integer as test_course_count
from public.courses
where offering_key = :'test_offering_key'
\gset
\if :test_course_count
\else
  \echo 'the selected test offering does not exist'
  \quit 3
\endif

select count(*)::integer as test_owner_count
from private.auth_user_links
where auth_user_id = :'test_owner_auth_user_id'::uuid
\gset
\if :test_owner_count
\else
  \echo 'the selected owner Auth user does not have a profile'
  \quit 3
\endif

begin;

-- The course definition is shared by the selected offering. Run this only on
-- a disposable/test offering or use a dedicated test course definition.
update private.course_definition_external_groups as organization
set external_group_id = :'test_organization_id',
    external_group_handle = :'test_organization_handle',
    repository_template_owner = :'test_template_owner',
    repository_template_name = :'test_template_repository',
    email_domain_enforced = true
from public.courses as course
where course.course_definition_key = organization.course_definition_key
  and course.offering_key = :'test_offering_key';

delete from private.course_definition_external_email_domains as domain
where domain.course_definition_key = (
  select course.course_definition_key
  from public.courses as course
  where course.offering_key = :'test_offering_key'
);

insert into private.course_definition_external_email_domains (
  course_definition_key,
  domain_suffix
)
select course.course_definition_key, lower(:'test_email_domain')
from public.courses as course
where course.offering_key = :'test_offering_key'
on conflict (course_definition_key, domain_suffix) do nothing;

create temporary table email_batch (
  email text primary key
) on commit drop;

select count(*)::integer as invalid_test_email_count
from regexp_split_to_table(
  replace(:'test_emails', E'\\n', E'\n'),
  E'\\r?\\n'
) as email
where btrim(email) <> ''
  and (
    btrim(email) !~ '^[^[:space:]@]+@[^[:space:]@]+$'
    or not (
      split_part(lower(btrim(email)), '@', 2) = lower(:'test_email_domain')
      or split_part(lower(btrim(email)), '@', 2) like '%.' || lower(:'test_email_domain')
    )
  )
\gset
\if :invalid_test_email_count
  \echo 'test_emails contains an invalid address or an address outside test_email_domain'
  \quit 3
\endif

insert into email_batch (email)
select lower(btrim(email))
from regexp_split_to_table(
  replace(:'test_emails', E'\\n', E'\n'),
  E'\\r?\\n'
) as email
where btrim(email) <> ''
  and (
    split_part(lower(btrim(email)), '@', 2) = lower(:'test_email_domain')
    or split_part(lower(btrim(email)), '@', 2) like '%.' || lower(:'test_email_domain')
  )
on conflict do nothing;

select count(*)::integer as test_email_count
from email_batch
\gset
\if :test_email_count
\else
  \echo 'test_emails did not contain any addresses in test_email_domain'
  \quit 3
\endif

-- Auth provisioning creates one application profile per email account.
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
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  batch.email,
  '', '', '', '', '', '', '', '',
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
from email_batch as batch
where not exists (
  select 1 from auth.users as existing where existing.email = batch.email
);

select private.ensure_auth_user_profile(auth_user.id)
from email_batch as batch
join auth.users as auth_user on auth_user.email = batch.email;

create temporary table batch_profiles on commit drop as
select batch.email, link.profile_id
from email_batch as batch
join auth.users as auth_user on auth_user.email = batch.email
join private.auth_user_links as link on link.auth_user_id = auth_user.id;

-- Seed approved requests directly. This intentionally tests the worker after
-- the approval decision; approval-RPC behavior is covered by pgTAP separately.
insert into private.course_access_requests (
  course_id,
  requester_profile_id,
  requested_role,
  reason,
  status,
  decision_source,
  decided_at,
  decided_by
)
select
  course.id,
  profile.profile_id,
  'learner',
  'real GitHub email invitation test',
  'approved',
  'owner',
  clock_timestamp(),
  link.profile_id
from batch_profiles as profile
cross join public.courses as course
join private.auth_user_links as link
  on link.auth_user_id = :'test_owner_auth_user_id'::uuid
where course.offering_key = :'test_offering_key'
  and not exists (
    select 1
    from private.course_access_requests as existing
    where existing.course_id = course.id
      and existing.requester_profile_id = profile.profile_id
  );

create temporary table batch_requests on commit drop as
select
  profile.email,
  profile.profile_id,
  course.id as course_id,
  request_row.id as access_request_id
from batch_profiles as profile
cross join public.courses as course
join lateral (
  select request_row.id
  from private.course_access_requests as request_row
  where request_row.course_id = course.id
    and request_row.requester_profile_id = profile.profile_id
    and request_row.status = 'approved'
  order by request_row.requested_at desc
  limit 1
) as request_row on true
where course.offering_key = :'test_offering_key';

-- Email-first access has no provider user ID until the invitation is accepted.
insert into private.external_course_access (
  course_id,
  profile_id,
  access_request_id,
  invitation_method,
  invitation_target,
  state
)
select
  batch.course_id,
  batch.profile_id,
  batch.access_request_id,
  'email',
  batch.email,
  'not_started'
from batch_requests as batch
on conflict (course_id, profile_id) do nothing;

-- Queue the real durable repository jobs before acceptance. The worker cannot
-- claim them until it has activated membership after GitHub acceptance.
insert into private.course_repository_provisioning (
  course_id,
  profile_id,
  course_definition_key,
  access_request_id,
  external_group_id,
  external_group_handle,
  repository_template_owner,
  repository_template_name
)
select
  batch.course_id,
  batch.profile_id,
  course.course_definition_key,
  batch.access_request_id,
  organization.external_group_id,
  organization.external_group_handle,
  organization.repository_template_owner,
  organization.repository_template_name
from batch_requests as batch
join public.courses as course on course.id = batch.course_id
join private.course_definition_external_groups as organization
  on organization.course_definition_key = course.course_definition_key
on conflict (course_id, profile_id) do nothing;

select
  email,
  profile_id,
  access_request_id,
  course_id
from batch_requests
order by email;

commit;
