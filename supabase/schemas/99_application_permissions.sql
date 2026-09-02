-- Final application-wide security policy.
-- Keep this file grouped by responsibility: RLS, function ownership, relation
-- access, and role-specific function execution.

-- ============================================================================
-- INTERNAL TABLE RLS
-- Internal tables are never directly exposed. These policies let trusted
-- database functions access them without granting browser roles any access.

-- Enable RLS on every private application table.
alter table private.course_access_requests enable row level security;
alter table private.course_roster_allowlist enable row level security;
alter table private.external_course_access enable row level security;
alter table private.course_repository_provisioning enable row level security;

-- Force RLS so even table owners cannot bypass these policies accidentally.
alter table private.course_access_requests force row level security;
alter table private.course_roster_allowlist force row level security;
alter table private.external_course_access force row level security;
alter table private.course_repository_provisioning force row level security;

create policy course_access_requests_function_access
on private.course_access_requests
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);

create policy course_roster_allowlist_function_access
on private.course_roster_allowlist
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);

create policy external_course_access_function_access
on private.external_course_access
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);
create policy course_repository_provisioning_function_access
on private.course_repository_provisioning
for all to ainigma_function_owner, ainigma_maintenance
using (true) with check (true);


-- ============================================================================
-- FUNCTION OWNER RELATION ACCESS
-- This NOLOGIN role receives only the relation privileges required by the SECURITY DEFINER functions it owns.
grant select, insert on private.course_definition_releases to ainigma_function_owner;
grant select on private.course_definition_external_groups to ainigma_function_owner;
grant select on private.course_definition_external_email_domains to ainigma_function_owner;
grant select, insert, update on public.courses to ainigma_function_owner;
grant select, insert, update on public.course_memberships to ainigma_function_owner;
grant select, insert on private.course_membership_events to ainigma_function_owner;
grant usage, select on sequence private.course_membership_events_id_seq to ainigma_function_owner;
grant select, insert, update on private.course_access_requests to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.course_roster_allowlist to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.external_course_access to ainigma_function_owner, ainigma_maintenance;
grant select, insert, update on private.course_repository_provisioning to ainigma_function_owner;

-- ============================================================================
-- SECURITY DEFINER FUNCTION OWNERSHIP
-- Ownership is separate from application login roles and is never a runtime connection identity.
alter function private.has_course_role(uuid, private.course_membership_role[]) owner to ainigma_function_owner;
alter function private.can_view_profile(uuid) owner to ainigma_function_owner;
alter function private.register_course_definition_release(text, text, text, text) owner to ainigma_function_owner;
alter function private.advance_open_course_offerings_to_release(uuid) owner to ainigma_function_owner;
alter function private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text, private.course_membership_verification) owner to ainigma_function_owner;
alter function private.add_course_membership(uuid, uuid, private.course_membership_role, uuid, text) owner to ainigma_function_owner;
alter function private.transition_course_membership(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) owner to ainigma_function_owner;
alter function private.transfer_course_ownership(uuid, uuid, uuid, text) owner to ainigma_function_owner;
alter function private.activate_course_membership_from_request(uuid, text) owner to ainigma_function_owner;
alter function private.list_external_course_access_to_reconcile() owner to ainigma_function_owner;
alter function private.record_external_course_access_invitation(uuid, uuid, private.external_invitation_method, text, text) owner to ainigma_function_owner;
alter function private.record_external_course_access_status(uuid, uuid, private.external_course_access_state, text) owner to ainigma_function_owner;
alter function private.record_external_course_access_check_failure(uuid, uuid, text) owner to ainigma_function_owner;
alter function private.record_external_course_access_membership_absence(uuid, uuid) owner to ainigma_function_owner;
alter function private.claim_course_repository_provisioning(integer, uuid, uuid) owner to ainigma_function_owner;
alter function private.complete_course_repository_provisioning(uuid, uuid, uuid, text, text, text) owner to ainigma_function_owner;
alter function private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean) owner to ainigma_function_owner;
alter function public.list_available_courses() owner to ainigma_function_owner;
alter function public.list_my_courses() owner to ainigma_function_owner;
alter function public.list_course_roster(text) owner to ainigma_function_owner;
alter function private.confirm_external_course_access(uuid, uuid, text, text, text, text, text) owner to ainigma_function_owner;
alter function public.request_course_access(text, text) owner to ainigma_function_owner;
alter function public.get_my_course_repository(text) owner to ainigma_function_owner;
alter function public.request_my_course_repository(text) owner to ainigma_function_owner;
alter function public.list_my_course_access_requests() owner to ainigma_function_owner;
alter function public.list_course_access_requests(text, private.course_access_request_status, text) owner to ainigma_function_owner;
alter function public.approve_course_access_requests(text, uuid[]) owner to ainigma_function_owner;
alter function public.reject_course_access_requests(text, uuid[], text) owner to ainigma_function_owner;

-- ============================================================================
-- DEFAULT FUNCTION LOCKDOWN
-- Remove PostgreSQL's default PUBLIC EXECUTE privilege before adding explicit
-- grants below. This keeps every function's caller set auditable.
revoke all on function
  private.reject_mutation(),
  private.has_course_role(uuid, private.course_membership_role[]),
  private.can_view_profile(uuid),
  private.register_course_definition_release(text, text, text, text),
  private.advance_open_course_offerings_to_release(uuid),
  private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text, private.course_membership_verification),
  private.add_course_membership(uuid, uuid, private.course_membership_role, uuid, text),
  private.transition_course_membership(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text),
  private.transfer_course_ownership(uuid, uuid, uuid, text),
  private.activate_course_membership_from_request(uuid, text),
  private.list_external_course_access_to_reconcile(),
  private.record_external_course_access_invitation(uuid, uuid, private.external_invitation_method, text, text),
  private.record_external_course_access_status(uuid, uuid, private.external_course_access_state, text),
  private.record_external_course_access_check_failure(uuid, uuid, text),
  private.record_external_course_access_membership_absence(uuid, uuid),
  private.claim_course_repository_provisioning(integer, uuid, uuid),
  private.complete_course_repository_provisioning(uuid, uuid, uuid, text, text, text),
  private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean),
  public.list_available_courses(),
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_my_courses(),
  public.list_course_roster(text),
  private.confirm_external_course_access(uuid, uuid, text, text, text, text, text),
  public.request_course_access(text, text),
  public.get_my_course_repository(text),
  public.request_my_course_repository(text),
  public.list_my_course_access_requests(),
  public.list_course_access_requests(text, private.course_access_request_status, text),
  public.approve_course_access_requests(text, uuid[]),
  public.reject_course_access_requests(text, uuid[], text)
from public, anon, authenticated, service_role, ainigma_maintenance;

-- ============================================================================
-- AUTHENTICATED BROWSER API
grant execute on function private.current_profile_id() to authenticated;
grant execute on function private.has_course_role(uuid, private.course_membership_role[]) to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;
-- ============================================================================
-- GENERAL MAINTENANCE API
grant execute on function private.ensure_auth_user_profile(uuid) to ainigma_maintenance;
grant execute on function private.sync_auth_identity(uuid) to ainigma_maintenance;
grant execute on function private.reconcile_auth_users() to ainigma_maintenance;
grant execute on function private.reconcile_auth_identities() to ainigma_maintenance;
grant execute on function private.report_identity_anomalies() to ainigma_maintenance;
grant execute on function private.register_course_definition_release(text, text, text, text) to ainigma_maintenance;
grant execute on function private.advance_open_course_offerings_to_release(uuid) to ainigma_maintenance;
grant execute on function private.branch_course_offering(text, uuid, text, uuid, timestamptz, timestamptz, text, private.course_membership_verification) to ainigma_maintenance;
grant execute on function private.add_course_membership(uuid, uuid, private.course_membership_role, uuid, text) to ainigma_maintenance;
grant execute on function private.transition_course_membership(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) to ainigma_maintenance;
grant execute on function private.transfer_course_ownership(uuid, uuid, uuid, text) to ainigma_maintenance;
grant execute on function private.activate_course_membership_from_request(uuid, text) to ainigma_function_owner, ainigma_maintenance;
grant execute on function private.list_external_course_access_to_reconcile() to ainigma_maintenance;
grant execute on function private.record_external_course_access_invitation(uuid, uuid, private.external_invitation_method, text, text) to ainigma_maintenance;
grant execute on function private.record_external_course_access_status(uuid, uuid, private.external_course_access_state, text) to ainigma_maintenance;
grant execute on function private.record_external_course_access_check_failure(uuid, uuid, text) to ainigma_maintenance;
grant execute on function private.record_external_course_access_membership_absence(uuid, uuid) to ainigma_maintenance;
grant execute on function private.claim_course_repository_provisioning(integer, uuid, uuid) to ainigma_maintenance;
grant execute on function private.complete_course_repository_provisioning(uuid, uuid, uuid, text, text, text) to ainigma_maintenance;
grant execute on function private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean) to ainigma_maintenance;
grant execute on function private.confirm_external_course_access(uuid, uuid, text, text, text, text, text) to ainigma_maintenance;

-- ============================================================================
-- EXTERNAL PROVISIONING WORKER API
-- This capability role has no direct table access. Deployment creates a separate restricted LOGIN role as its member.
grant usage on schema private to ainigma_external_provisioning_worker;
grant execute on function private.list_external_course_access_to_reconcile() to ainigma_external_provisioning_worker;
grant execute on function private.record_external_course_access_invitation(uuid, uuid, private.external_invitation_method, text, text) to ainigma_external_provisioning_worker;
grant execute on function private.record_external_course_access_status(uuid, uuid, private.external_course_access_state, text) to ainigma_external_provisioning_worker;
grant execute on function private.record_external_course_access_check_failure(uuid, uuid, text) to ainigma_external_provisioning_worker;
grant execute on function private.record_external_course_access_membership_absence(uuid, uuid) to ainigma_external_provisioning_worker;
grant execute on function private.confirm_external_course_access(uuid, uuid, text, text, text, text, text) to ainigma_external_provisioning_worker;
grant execute on function private.claim_course_repository_provisioning(integer, uuid, uuid) to ainigma_external_provisioning_worker;
grant execute on function private.complete_course_repository_provisioning(uuid, uuid, uuid, text, text, text) to ainigma_external_provisioning_worker;
grant execute on function private.record_course_repository_provisioning_failure(uuid, uuid, uuid, text, boolean) to ainigma_external_provisioning_worker;

-- ============================================================================
-- AUTHENTICATED PUBLIC RPC API
grant execute on function
  public.get_my_profile(),
  public.update_my_profile(text),
  public.list_available_courses(),
  public.list_my_courses(),
  public.list_course_roster(text),
  public.request_course_access(text, text),
  public.get_my_course_repository(text),
  public.request_my_course_repository(text),
  public.list_my_course_access_requests()
to authenticated;
grant execute on function public.list_available_courses() to anon;
grant execute on function
  public.list_course_access_requests(text, private.course_access_request_status, text),
  public.approve_course_access_requests(text, uuid[]),
  public.reject_course_access_requests(text, uuid[], text)
to authenticated;

-- ============================================================================
-- PUBLIC TABLE RLS
-- Enable RLS before defining the public relation policies.
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_memberships enable row level security;

-- Force RLS so relation owners cannot bypass the public access model.
alter table public.profiles force row level security;
alter table public.courses force row level security;
alter table public.course_memberships force row level security;

-- Function-owner policies allow trusted functions to access public relations
-- without recursive browser policies or BYPASSRLS.
create policy profiles_function_owner_access
on public.profiles
for all
to ainigma_function_owner
using (true)
with check (true);

create policy courses_function_owner_access
on public.courses
for all
to ainigma_function_owner
using (true)
with check (true);

create policy course_memberships_function_owner_access
on public.course_memberships
for all
to ainigma_function_owner
using (true)
with check (true);

create policy profiles_select_authorized
on public.profiles
for select
to authenticated
using ((select private.can_view_profile(id)));

create policy profiles_update_own_display_name
on public.profiles
for update
to authenticated
using (id = (select private.current_profile_id()))
with check (id = (select private.current_profile_id()));

create policy courses_select_enrolled
on public.courses
for select
to authenticated
using (
  (
    status = 'published'
    and (select private.has_course_role(id, array['owner', 'instructor', 'learner']::private.course_membership_role[]))
  )
  or (
    status = 'draft'
    and (select private.has_course_role(id, array['owner', 'instructor']::private.course_membership_role[]))
  )
);

create policy course_memberships_select_authorized
on public.course_memberships
for select
to authenticated
using (
  profile_id = (select private.current_profile_id())
  or (select private.has_course_role(course_id, array['owner', 'instructor']::private.course_membership_role[]))
);

-- ============================================================================
-- DIRECT TABLE ACCESS LOCKDOWN
grant usage on schema public to authenticated;

-- Direct relation access.
-- Browser and service roles use the RPC surface; table access is denied even
-- when a table lives in an exposed schema.
revoke all on public.profiles, public.courses, public.course_memberships
  from public, anon, authenticated, service_role;
revoke all on private.auth_users,
  private.auth_identities,
  private.auth_user_links,
  private.profile_identifiers,
  private.course_membership_events,
  private.course_access_requests,
  private.course_roster_allowlist,
  private.external_course_access,
  private.course_repository_provisioning
  from public, anon, authenticated, service_role;
revoke all on sequence private.course_membership_events_id_seq
  from public, anon, authenticated, service_role;
