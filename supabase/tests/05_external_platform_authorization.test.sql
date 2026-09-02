begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(42);

-- These are database contract tests. A GitHub organization snapshot is not
-- stored locally, so the trusted confirmation RPC represents the worker's
-- observation of an active GitHub member. Direct assertions run as the local
-- test connection; provider RPCs remain security-definer functions.

-- A GitHub member without an access request must not be enrolled.
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000003'),
    '88000001',
    'ainigma-dev-course-org',
    null,
    '90000003',
    'ainigma-local-emptyLearner'
  )$$,
  '23503',
  'external_access_not_started',
  'organization membership alone cannot create course access'
);
select extensions.is(
  (select count(*)::bigint
   from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a member without an access request has no local course membership'
);
select extensions.is(
  (select count(*)::bigint
   from private.list_external_course_access_to_reconcile() access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a member without an access request is not returned for reconciliation'
);
reset role;

-- A pending request creates neither external access nor local membership.
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000004', true);
reset role;
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004'),
    'external_user_id',
    '90000004',
    '99000004'
  )$$,
  '23503',
  'external_access_not_started',
  'a pending request cannot start external invitation provisioning'
);
select extensions.is(
  (select count(*)::bigint
   from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a pending request has no external access record'
);
select extensions.is(
  (select count(*)::bigint
   from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a pending request has no local membership'
);
reset role;

-- Approval for a non-member starts invitation provisioning, but does not
-- activate local access yet. The empty learner is the non-member fixture.
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000003', true);
select public.request_course_access('test-course-a-local', 'external platform test');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select public.approve_course_access_requests('test-course-a-local');
reset role;
select extensions.is(
  (select count(*)::bigint
   from private.list_external_course_access_to_reconcile() access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')
     and access_row.state = 'not_started'),
  1::bigint,
  'an approved request without an invitation is returned for reconciliation'
);
select private.record_external_course_access_invitation(
  (select id from public.courses where offering_key = 'test-course-a-local'),
  (select profile_id from private.auth_user_links
   where auth_user_id = '50000000-0000-0000-0000-000000000003'),
  'external_user_id',
  '90000003',
  '99000003'
);
select extensions.is(
  (select state::text from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'invitation_pending',
  'the non-member invitation workflow starts after approval'
);
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000003'),
    '88000001',
    'ainigma-dev-course-org',
    null,
    '90000003',
    'ainigma-local-emptyLearner'
  )$$,
  '42501',
  'external_invitation_mismatch',
  'an invitation-backed access row cannot be confirmed without its invitation ID'
);
reset role;

select set_config(
  'ainigma_external_platform_test.pending_request_id',
  (
    select request_row.id::text
    from private.course_access_requests request_row
    join private.auth_user_links link on link.profile_id = request_row.requester_profile_id
    where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
      and request_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')
  ),
  true
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select extensions.is(
  public.approve_course_access_requests(
    'test-course-a-local',
    array[current_setting('ainigma_external_platform_test.pending_request_id')::uuid]
  ),
  0,
  'already approved requests are not approved twice'
);
reset role;

-- Approval for an existing organization member can confirm access without an
-- invitation identifier. The seeded pending learner represents that member.
reset role;
select private.confirm_external_course_access(
  (select id from public.courses where offering_key = 'test-course-a-local'),
  (select profile_id from private.auth_user_links
   where auth_user_id = '50000000-0000-0000-0000-000000000004'),
  '88000001',
  'ainigma-dev-course-org',
  null,
  '90000004',
  'ainigma-local-pendingLearner'
);
select extensions.is(
  (select state::text from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'active',
  'an existing organization member can be confirmed after approval'
);
select extensions.throws_ok(
  $$select private.confirm_external_course_access(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004'),
    '88000001',
    'ainigma-dev-course-org',
    '99000004',
    '90000004',
    'ainigma-local-pendingLearner'
  )$$,
  '42501',
  'external_invitation_mismatch',
  'an existing-member access row cannot be confirmed with a fabricated invitation ID'
);
select extensions.ok(
  (select external_invitation_id is null from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'an existing organization member has no invitation identifier'
);
select extensions.is(
  (select membership.status::text from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'active',
  'existing organization membership creates local course membership'
);
select extensions.is(
  (select membership.created_from_access_request_id
   from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  (select access_row.access_request_id
   from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'the local membership records its approved access request'
);
select extensions.is(
  (select count(*)::integer
   from public.course_memberships membership
   join private.external_course_access access_row
     on access_row.course_id = membership.course_id
    and access_row.profile_id = membership.profile_id
   join private.course_access_requests request_row
     on request_row.id = access_row.access_request_id
   where membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')
     and membership.profile_id = access_row.profile_id
     and membership.status = 'active'
     and access_row.state = 'active'
     and request_row.status <> 'approved'),
  0,
  'every externally activated membership has an approved access request'
);
select private.confirm_external_course_access(
  (select id from public.courses where offering_key = 'test-course-a-local'),
  (select profile_id from private.auth_user_links
   where auth_user_id = '50000000-0000-0000-0000-000000000004'),
  '88000001',
  'ainigma-dev-course-org',
  null,
  '90000004',
  'ainigma-local-pendingLearner'
);
select extensions.is(
  (select count(*)::bigint from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  1::bigint,
  'repeated confirmation does not create a duplicate membership'
);
select extensions.is(
  (select count(*)::bigint from private.course_membership_events event_row
   join private.auth_user_links link on link.profile_id = event_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and event_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')
     and event_row.event_kind = 'created'
     and event_row.new_role = 'learner'
     and event_row.new_status = 'active'),
  1::bigint,
  'repeated confirmation does not create a duplicate membership event'
);
reset role;

-- A rejected request never creates external access or local membership.
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000006', true);
select extensions.is(
  (public.request_course_access('test-course-a-local', 'rejection test') ->> 'state'),
  'pending',
  'a learner can submit a request that will be rejected'
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select extensions.is(
  public.reject_course_access_requests('test-course-a-local'),
  1,
  'the owner can reject a pending request'
);
reset role;
select extensions.is(
  (select status::text from private.course_access_requests request_row
   join private.auth_user_links link on link.profile_id = request_row.requester_profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000006'
     and request_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'rejected',
  'the request remains rejected'
);
select extensions.is(
  (select count(*)::bigint from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000006'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a rejected request has no external access'
);
select extensions.is(
  (select count(*)::bigint from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000006'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0::bigint,
  'a rejected request has no local membership'
);
reset role;

-- Three consecutive complete snapshots without the member revoke access.
select extensions.is(
  private.record_external_course_access_membership_absence(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004')
  ),
  false,
  'one missing organization snapshot does not revoke access'
);
select private.confirm_external_course_access(
  (select id from public.courses where offering_key = 'test-course-a-local'),
  (select profile_id from private.auth_user_links
   where auth_user_id = '50000000-0000-0000-0000-000000000004'),
  '88000001',
  'ainigma-dev-course-org',
  null,
  '90000004',
  'ainigma-local-pendingLearner'
);
select extensions.is(
  (select consecutive_membership_absences
   from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  0,
  'a confirmed member reappearing resets the absence counter'
);
select extensions.is(
  private.record_external_course_access_membership_absence(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004')
  ),
  false,
  'one missing snapshot after reappearance does not revoke access'
);
select extensions.is(
  private.record_external_course_access_membership_absence(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004')
  ),
  false,
  'two missing snapshots after reappearance do not revoke access'
);
select extensions.is(
  private.record_external_course_access_membership_absence(
    (select id from public.courses where offering_key = 'test-course-a-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000004')
  ),
  true,
  'the configured third absence after reappearance revokes access'
);
select extensions.is(
  (select state::text from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'revoked',
  'external access is revoked after the absence threshold'
);
select extensions.is(
  (select status::text from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-a-local')),
  'revoked',
  'local course membership is revoked with external access'
);

-- First-party SSO can use the same request/approval boundary without requiring
-- a second organization membership check. The configured provider remains
-- available for optional repository provisioning.
update public.courses
set membership_verification = 'approval_only'
where offering_key = 'test-course-b-local';

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000003', true);
select extensions.is(
  (public.request_course_access('test-course-b-local', 'direct SSO request')->>'state'),
  'pending',
  'approval-only access still requires an access request'
);
reset role;
select extensions.is(
  (select count(*)::bigint
   from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  0::bigint,
  'approval-only requests do not create external access records'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select extensions.is(
  public.approve_course_access_requests('test-course-b-local'),
  1,
  'owner approval activates an approval-only learner'
);
reset role;
select extensions.is(
  (select status::text
   from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  'active',
  'approval-only access creates local course membership'
);
select extensions.is(
  (select membership.created_from_access_request_id
   from public.course_memberships membership
   join private.auth_user_links link on link.profile_id = membership.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and membership.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  (select request_row.id
   from private.course_access_requests request_row
   join private.auth_user_links link on link.profile_id = request_row.requester_profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and request_row.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  'approval-only membership records its approved request'
);
select extensions.throws_ok(
  $$select private.record_external_course_access_invitation(
    (select id from public.courses where offering_key = 'test-course-b-local'),
    (select profile_id from private.auth_user_links
     where auth_user_id = '50000000-0000-0000-0000-000000000003'),
    'external_user_id',
    '90000003',
    '99100003'
  )$$,
  '42501',
  'external_access_not_required',
  'external invitations cannot bypass approval-only course access'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000003', true);
select extensions.is(
  (public.request_my_course_repository('test-course-b-local')->>'state'),
  'queued',
  'an approval-only learner can request a repository'
);
reset role;
select extensions.is(
  (select external_user_handle
   from private.claim_course_repository_provisioning(
     1,
     (select id from public.courses where offering_key = 'test-course-b-local'),
     (select profile_id from private.auth_user_links
      where auth_user_id = '50000000-0000-0000-0000-000000000003'))),
  'ainigma-local-emptylearner',
  'repository provisioning resolves the optional provider identity from the profile'
);
select extensions.is(
  (select repository_name
   from private.course_repository_provisioning repository
   join private.auth_user_links link on link.profile_id = repository.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000003'
     and repository.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  'submissions-test-course-b-local-ainigma-local-emptylearner',
  'approval-only repository claims keep deterministic repository naming'
);

-- Allowlist auto-approval still creates the request first, then activates the
-- local membership without consulting the external provider.
update public.courses
set enrollment_mode = 'allowlist_auto'
where offering_key = 'test-course-b-local';
insert into private.course_roster_allowlist (
  course_id,
  identifier_kind,
  identifier_issuer,
  identifier_scheme_version,
  normalized_identifier_value,
  source,
  imported_by
)
select
  (select id from public.courses where offering_key = 'test-course-b-local'),
  identifier.kind,
  identifier.issuer,
  identifier.scheme_version,
  identifier.normalized_value,
  'direct-sso-test',
  (select profile_id from private.auth_user_links
   where auth_user_id = '50000000-0000-0000-0000-000000000001')
from private.profile_identifiers identifier
join private.auth_user_links link on link.profile_id = identifier.profile_id
where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
  and identifier.kind = 'email'
  and identifier.revoked_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000004', true);
select extensions.is(
  (public.request_course_access('test-course-b-local', 'allowlist direct SSO request')->>'state'),
  'active',
  'allowlisted approval-only access activates immediately after the request'
);
reset role;
select extensions.is(
  (select count(*)::bigint
   from private.external_course_access access_row
   join private.auth_user_links link on link.profile_id = access_row.profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and access_row.course_id = (select id from public.courses where offering_key = 'test-course-b-local')),
  0::bigint,
  'allowlisted approval-only access has no external access record'
);
select extensions.is(
  (select request_row.decision_source
   from private.course_access_requests request_row
   join private.auth_user_links link on link.profile_id = request_row.requester_profile_id
   where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
     and request_row.course_id = (select id from public.courses where offering_key = 'test-course-b-local')
   order by request_row.requested_at desc
   limit 1),
  'allowlist',
  'allowlist auto-approval remains recorded on the request'
);

select * from extensions.finish();
rollback;
