set local check_function_bodies = off;

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "service_role";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "service_role";

create table "private"."auth_user_links" (
  "auth_user_id" uuid                     not null,
  "profile_id"   uuid                     not null,
  "created_at"   timestamp with time zone not null default clock_timestamp(),
  constraint "auth_user_links_pkey" primary key (auth_user_id)
);

create table "private"."course_access_requests" (
  "id"                   uuid                     not null default gen_random_uuid(),
  "course_id"            uuid                     not null,
  "requester_profile_id" uuid                     not null,
  "reason"               text,
  "decision_source"      text                     not null default 'owner'::text,
  "requested_at"         timestamp with time zone not null default clock_timestamp(),
  "decided_at"           timestamp with time zone,
  "decided_by"           uuid,
  "decision_reason"      text,
  constraint "course_access_requests_decision_source_check" check ((decision_source = ANY (ARRAY['owner'::text, 'allowlist'::text]))),
  constraint "course_access_requests_id_course_profile_unique" unique (id, course_id, requester_profile_id),
  constraint "course_access_requests_pkey" primary key (id),
  constraint "course_access_requests_reason_check" check (((reason IS NULL) OR ((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000)))))
);

alter table "private"."course_access_requests"
  enable row level security;

alter table "private"."course_access_requests"
  force row level security;

create table "private"."course_definition_external_email_domains" (
  "course_definition_key" text not null,
  "domain_suffix"         text not null,
  constraint "course_definition_external_email_domains_pkey" primary key (course_definition_key, domain_suffix),
  constraint "course_definition_external_email_domains_suffix_check"
    check
    (((domain_suffix = lower(btrim(domain_suffix))) AND (domain_suffix !~ '[[:space:]@]'::text) AND (domain_suffix !~ '(^[.]|[.]$|[.][.])'::text) AND (domain_suffix ~
    '^[a-z0-9-]+([.][a-z0-9-]+)*$'::text)))
);

create table "private"."course_definition_external_groups" (
  "course_definition_key" text                     not null,
  "provider_kind"         text                     not null default 'github'::text,
  "provider_issuer"       text                     not null default 'github.com'::text,
  "external_group_id"     text                     not null,
  "external_group_handle" text                     not null,
  "email_domain_enforced" boolean                  not null default true,
  "created_at"            timestamp with time zone not null default clock_timestamp(),
  constraint "course_definition_external_groups_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "course_definition_external_groups_group_id_check"
    check (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255)))),
  constraint "course_definition_external_groups_org_slug_check"
    check (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255)))),
  constraint "course_definition_external_groups_pkey" primary key (course_definition_key),
  constraint "course_definition_external_groups_provider_issuer_check"
    check
    (((provider_issuer = btrim(provider_issuer)) AND ((char_length(provider_issuer) >= 1) AND (char_length(provider_issuer) <= 255)) AND (provider_issuer !~ '[[:space:]]'::text))),
  constraint "course_definition_external_groups_provider_kind_check" check (((provider_kind = btrim(provider_kind)) AND (provider_kind ~ '^[a-z][a-z0-9_]{0,63}$'::text)))
);

create table "private"."course_definition_releases" (
  "id"                    uuid                     not null default gen_random_uuid(),
  "course_definition_key" text                     not null,
  "source_commit_sha"     text                     not null,
  "course_release_digest" text                     not null,
  "artifact_ref"          text                     not null,
  "created_at"            timestamp with time zone not null default clock_timestamp(),
  constraint "course_definition_releases_artifact_ref_check"
    check (((artifact_ref = btrim(artifact_ref)) AND ((char_length(artifact_ref) >= 1) AND (char_length(artifact_ref) <= 2048)))),
  constraint "course_definition_releases_definition_digest_unique" unique (course_definition_key, course_release_digest),
  constraint "course_definition_releases_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "course_definition_releases_digest_check" check ((course_release_digest ~ '^[0-9a-f]{64}$'::text)),
  constraint "course_definition_releases_id_definition_key_unique" unique (id, course_definition_key),
  constraint "course_definition_releases_pkey" primary key (id),
  constraint "course_definition_releases_source_commit_sha_check" check ((source_commit_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'::text))
);

create table "private"."course_membership_events" (
  "id"               bigint                   generated always as identity not null,
  "course_id"        uuid                     not null,
  "profile_id"       uuid                     not null,
  "event_kind"       text                     not null,
  "actor_profile_id" uuid,
  "reason"           text                     not null,
  "created_at"       timestamp with time zone not null default clock_timestamp(),
  constraint "course_membership_events_kind_check" check ((event_kind = ANY (ARRAY['created'::text, 'transitioned'::text]))),
  constraint "course_membership_events_pkey" primary key (id),
  constraint "course_membership_events_reason_check" check (((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000))))
);

create table "private"."course_repository_provisioning" (
  "course_id"               uuid                     not null,
  "profile_id"              uuid                     not null,
  "access_request_id"       uuid                     not null,
  "external_group_id"       text                     not null,
  "external_group_handle"   text                     not null,
  "repository_name"         text,
  "external_repository_id"  text,
  "external_repository_url" text,
  "state"                   text                     not null default 'queued'::text,
  "attempt_count"           integer                  not null default 0,
  "lease_token"             uuid,
  "lease_expires_at"        timestamp with time zone,
  "next_attempt_at"         timestamp with time zone default clock_timestamp(),
  "last_error"              text,
  "created_at"              timestamp with time zone not null default clock_timestamp(),
  "updated_at"              timestamp with time zone not null default clock_timestamp(),
  constraint "course_repository_provisioning_attempt_check" check ((attempt_count >= 0)),
  constraint "course_repository_provisioning_error_check" check ((((state = ANY (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS
    NOT NULL) AND (last_error = btrim(last_error)) AND ((char_length(last_error) >= 1) AND (char_length(last_error) <= 1000))) OR
    ((state <> ALL (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS NULL)))),
  constraint "course_repository_provisioning_group_handle_check"
    check (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255)))),
  constraint "course_repository_provisioning_group_id_check"
    check (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255)))),
  constraint "course_repository_provisioning_lease_check" check ((((state = 'provisioning'::text) AND (lease_token IS NOT NULL) AND (lease_expires_at IS
    NOT NULL)) OR ((state <> 'provisioning'::text) AND (lease_token IS NULL) AND (lease_expires_at IS NULL)))),
  constraint "course_repository_provisioning_name_check"
    check (((repository_name IS NULL) OR ((repository_name = btrim(repository_name)) AND ((char_length(repository_name) >= 1) AND (char_length(repository_name) <= 100))))),
  constraint "course_repository_provisioning_next_attempt_check" check ((((state = ANY (ARRAY['queued'::text, 'retry_wait'::text, 'provisioning'::text])) AND (next_attempt_at IS
    NOT NULL)) OR ((state = ANY (ARRAY['ready'::text, 'blocked'::text])) AND (next_attempt_at IS NULL)))),
  constraint "course_repository_provisioning_pkey" primary key (course_id, profile_id),
  constraint "course_repository_provisioning_ready_shape_check" check ((((state = 'ready'::text) AND (repository_name IS NOT NULL) AND (external_repository_id IS
    NOT NULL) AND (external_repository_url IS NOT NULL)) OR (state <> 'ready'::text))),
  constraint "course_repository_provisioning_repository_id_check"
    check
    (((external_repository_id IS NULL) OR ((external_repository_id = btrim(external_repository_id)) AND ((char_length(external_repository_id) >= 1) AND
    (char_length(external_repository_id) <= 255))))),
  constraint "course_repository_provisioning_state_check" check ((state = ANY (ARRAY['queued'::text, 'provisioning'::text, 'retry_wait'::text, 'ready'::text, 'blocked'::text]))),
  constraint "course_repository_provisioning_url_check"
    check
    (((external_repository_url IS NULL) OR ((external_repository_url = btrim(external_repository_url)) AND ((char_length(external_repository_url) >= 1) AND
    (char_length(external_repository_url) <= 2048)))))
);

alter table "private"."course_repository_provisioning"
  enable row level security;

alter table "private"."course_repository_provisioning"
  force row level security;

create table "private"."course_roster_allowlist" (
  "id"                          uuid                     not null default gen_random_uuid(),
  "course_id"                   uuid                     not null,
  "identifier_kind"             text                     not null,
  "identifier_issuer"           text                     not null,
  "identifier_scheme_version"   integer                  not null,
  "normalized_identifier_value" text                     not null,
  "source"                      text                     not null,
  "status"                      text                     not null default 'active'::text,
  "imported_at"                 timestamp with time zone not null default clock_timestamp(),
  "imported_by"                 uuid,
  "revoked_at"                  timestamp with time zone,
  constraint "course_roster_allowlist_issuer_check"
    check (((identifier_issuer = btrim(identifier_issuer)) AND ((char_length(identifier_issuer) >= 1) AND (char_length(identifier_issuer) <= 255)))),
  constraint "course_roster_allowlist_kind_check" check ((identifier_kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'student_identifier'::text]))),
  constraint "course_roster_allowlist_pkey" primary key (id),
  constraint "course_roster_allowlist_revoked_shape_check" check ((((status = 'active'::text) AND (revoked_at IS NULL)) OR ((status = 'revoked'::text) AND (revoked_at IS
    NOT NULL)))),
  constraint "course_roster_allowlist_scheme_check" check ((identifier_scheme_version > 0)),
  constraint "course_roster_allowlist_source_check" check (((source = btrim(source)) AND ((char_length(source) >= 1) AND (char_length(source) <= 255)))),
  constraint "course_roster_allowlist_status_check" check ((status = ANY (ARRAY['active'::text, 'revoked'::text]))),
  constraint "course_roster_allowlist_value_check"
    check
    (((normalized_identifier_value = btrim(normalized_identifier_value)) AND ((char_length(normalized_identifier_value) >= 1) AND (char_length(normalized_identifier_value) <=
    512))))
);

alter table "private"."course_roster_allowlist"
  enable row level security;

alter table "private"."course_roster_allowlist"
  force row level security;

create table "private"."external_course_access" (
  "course_id"                       uuid                     not null,
  "profile_id"                      uuid                     not null,
  "access_request_id"               uuid                     not null,
  "external_group_id"               text,
  "external_group_handle"           text,
  "external_user_id"                text                     not null,
  "external_user_handle"            text,
  "external_invitation_id"          text,
  "invitation_method"               text                     not null default 'email'::text,
  "invitation_target"               text,
  "invited_at"                      timestamp with time zone,
  "accepted_at"                     timestamp with time zone,
  "last_checked_at"                 timestamp with time zone,
  "failure_code"                    text,
  "consecutive_membership_absences" integer                  not null default 0,
  constraint "external_course_access_failure_check"
    check (((failure_code IS NULL) OR ((failure_code = btrim(failure_code)) AND ((char_length(failure_code) >= 1) AND (char_length(failure_code) <= 255))))),
  constraint "external_course_access_group_handle_check"
    check
    (((external_group_handle IS NULL) OR ((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND
    (char_length(external_group_handle) <= 255))))),
  constraint "external_course_access_invitation_id_check"
    check
    (((external_invitation_id IS NULL) OR ((external_invitation_id = btrim(external_invitation_id)) AND ((char_length(external_invitation_id) >= 1) AND
    (char_length(external_invitation_id) <= 255))))),
  constraint "external_course_access_invitation_method_check" check ((invitation_method = ANY (ARRAY['email'::text, 'external_user_id'::text]))),
  constraint "external_course_access_invitation_target_check"
    check
    (((invitation_target IS NULL) OR ((invitation_target = btrim(invitation_target)) AND ((char_length(invitation_target) >= 1) AND (char_length(invitation_target) <= 512))))),
  constraint "external_course_access_membership_absences_check" check ((consecutive_membership_absences >= 0)),
  constraint "external_course_access_pkey" primary key (course_id, profile_id),
  constraint "external_course_access_repository_identity_unique" unique (course_id, profile_id, access_request_id, external_group_id, external_group_handle),
  constraint "external_course_access_user_handle_check"
    check
    (((external_user_handle IS NULL) OR ((external_user_handle = btrim(external_user_handle)) AND ((char_length(external_user_handle) >= 1) AND (char_length(external_user_handle)
    <= 255)) AND (external_user_handle !~ '[[:space:]]'::text)))),
  constraint "external_course_access_user_id_check"
    check (((external_user_id = btrim(external_user_id)) AND ((char_length(external_user_id) >= 1) AND (char_length(external_user_id) <= 255))))
);

alter table "private"."external_course_access"
  enable row level security;

alter table "private"."external_course_access"
  force row level security;

create table "private"."profile_identifiers" (
  "id"                   uuid                     not null default gen_random_uuid(),
  "profile_id"           uuid                     not null,
  "kind"                 text                     not null,
  "issuer"               text                     not null,
  "scheme_version"       integer                  not null,
  "normalized_value"     text                     not null,
  "verified_at"          timestamp with time zone not null,
  "last_verified_at"     timestamp with time zone not null,
  "revoked_at"           timestamp with time zone,
  "source_auth_user_id"  uuid,
  "provider_identity_id" text,
  "created_at"           timestamp with time zone not null default clock_timestamp(),
  "updated_at"           timestamp with time zone not null default clock_timestamp(),
  constraint "profile_identifiers_issuer_check" check (((issuer = btrim(issuer)) AND ((char_length(issuer) >= 1) AND (char_length(issuer) <= 255)))),
  constraint "profile_identifiers_kind_check" check ((kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'external_user_handle'::text, 'student_identifier'::text]))),
  constraint "profile_identifiers_normalized_value_check"
    check (((normalized_value = btrim(normalized_value)) AND ((char_length(normalized_value) >= 1) AND (char_length(normalized_value) <= 512)))),
  constraint "profile_identifiers_pkey" primary key (id),
  constraint "profile_identifiers_provider_identity_id_check"
    check (((provider_identity_id IS NULL) OR ((char_length(provider_identity_id) >= 1) AND (char_length(provider_identity_id) <= 255)))),
  constraint "profile_identifiers_scheme_version_check" check ((scheme_version > 0)),
  constraint "profile_identifiers_verification_window_check" check (((last_verified_at >= verified_at) AND ((revoked_at IS NULL) OR (revoked_at >= verified_at))))
);

create table "public"."course_memberships" (
  "course_id"                      uuid                     not null,
  "profile_id"                     uuid                     not null,
  "created_at"                     timestamp with time zone not null default clock_timestamp(),
  "suspended_at"                   timestamp with time zone,
  "revoked_at"                     timestamp with time zone,
  "created_from_access_request_id" uuid,
  constraint "course_memberships_pkey" primary key (course_id, profile_id)
);

alter table "public"."course_memberships"
  enable row level security;

alter table "public"."course_memberships"
  force row level security;

create table "public"."courses" (
  "id"                           uuid                     not null default gen_random_uuid(),
  "offering_key"                 text                     not null,
  "course_definition_key"        text                     not null,
  "course_definition_release_id" uuid                     not null,
  "code"                         text                     not null,
  "starts_at"                    timestamp with time zone,
  "ends_at"                      timestamp with time zone,
  "external_url"                 text,
  "created_at"                   timestamp with time zone not null default clock_timestamp(),
  "updated_at"                   timestamp with time zone not null default clock_timestamp(),
  constraint "courses_code_check" check (((code = btrim(code)) AND ((char_length(code) >= 1) AND (char_length(code) <= 32)))),
  constraint "courses_course_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "courses_external_url_check" check (((external_url IS NULL) OR ((char_length(external_url) <= 2048) AND (external_url ~ '^https?://'::text)))),
  constraint "courses_offering_key_check" check ((offering_key ~ '^[a-z][a-z0-9-]{2,127}$'::text)),
  constraint "courses_offering_key_key" unique (offering_key),
  constraint "courses_pkey" primary key (id),
  constraint "courses_time_window_check" check (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at)))
);

alter table "public"."courses"
  enable row level security;

alter table "public"."courses"
  force row level security;

create table "public"."profiles" (
  "id"           uuid                     not null default gen_random_uuid(),
  "display_name" text                     not null default 'Learner'::text,
  "created_at"   timestamp with time zone not null default clock_timestamp(),
  "updated_at"   timestamp with time zone not null default clock_timestamp(),
  constraint "profiles_display_name_check"
    check (((display_name IS NULL) OR ((display_name = btrim(display_name)) AND ((char_length(display_name) >= 1) AND (char_length(display_name) <= 100))))),
  constraint "profiles_pkey" primary key (id)
);

alter table "public"."profiles"
  enable row level security;

alter table "public"."profiles"
  force row level security;

create type "private"."course_access_request_status" as enum (
  'pending',
  'approved',
  'rejected',
  'cancelled'
);

alter table "private"."course_access_requests"
  add column "status" private.course_access_request_status not null default 'pending'::private.course_access_request_status;

create type "private"."course_enrollment_mode" as enum (
  'approval_required',
  'allowlist_auto',
  'closed'
);

alter table "public"."courses"
  add column "enrollment_mode" private.course_enrollment_mode not null default 'approval_required'::private.course_enrollment_mode;

create type "private"."course_membership_role" as enum (
  'owner',
  'instructor',
  'learner'
);

alter table "private"."course_access_requests"
  add column "requested_role" private.course_membership_role not null default 'learner'::private.course_membership_role;

alter table "private"."course_membership_events"
  add column "previous_role" private.course_membership_role;

alter table "private"."course_membership_events"
  add column "new_role" private.course_membership_role not null;

alter table "private"."course_roster_allowlist"
  add column "role" private.course_membership_role not null default 'learner'::private.course_membership_role;

alter table "public"."course_memberships"
  add column "role" private.course_membership_role not null;

create type "private"."course_membership_status" as enum (
  'active',
  'suspended',
  'revoked'
);

alter table "private"."course_membership_events"
  add column "previous_status" private.course_membership_status;

alter table "private"."course_membership_events"
  add column "new_status" private.course_membership_status not null;

alter table "public"."course_memberships"
  add column "status" private.course_membership_status not null default 'active'::private.course_membership_status;

create type "private"."course_offering_status" as enum (
  'draft',
  'published',
  'archived'
);

alter table "public"."courses"
  add column "status" private.course_offering_status not null default 'draft'::private.course_offering_status;

create type "private"."external_course_access_state" as enum (
  'not_started',
  'invitation_pending',
  'sso_required',
  'active',
  'failed',
  'revoked'
);

alter table "private"."external_course_access"
  add column "state" private.external_course_access_state not null default 'not_started'::private.external_course_access_state;

create or replace function private.add_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_role             private.course_membership_role,
  p_actor_profile_id uuid,
  p_reason           text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_actor_role private.course_membership_role;
begin
  if p_role is null or p_role not in ('instructor', 'learner') then
    if p_role = 'owner' then
      raise exception using errcode = '42501', message = 'course_owner_transfer_required';
    end if;
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (p_role in ('owner', 'instructor') and v_actor_role <> 'owner')
    or (p_role = 'learner' and v_actor_role not in ('owner', 'instructor'))
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (p_course_id, p_profile_id, p_role, 'active');

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'created',
    p_role,
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;

alter function "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) owner to "ainigma_function_owner";

create or replace function private.advance_open_course_offerings_to_release (
  p_course_definition_release_id uuid
)
  returns integer
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_definition_key text;
  v_updated_count integer;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  update public.courses as course
  set course_definition_release_id = p_course_definition_release_id
  where course.course_definition_key = v_course_definition_key
    and course.status <> 'archived'
    and course.course_definition_release_id <> p_course_definition_release_id;

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end
$function$;

alter function "private"."advance_open_course_offerings_to_release"(uuid) owner to "ainigma_function_owner";

create or replace function private.branch_course_offering (
  p_offering_key                 text,
  p_course_definition_release_id uuid,
  p_code                         text,
  p_owner_profile_id             uuid,
  p_starts_at                    timestamp with time zone default null::timestamp with time zone,
  p_ends_at                      timestamp with time zone default null::timestamp with time zone,
  p_external_url                 text                     default null::text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_course_definition_key text;
begin
  select release.course_definition_key
  into v_course_definition_key
  from private.course_definition_releases as release
  where release.id = p_course_definition_release_id;

  if v_course_definition_key is null then
    raise exception using errcode = '23503', message = 'course_definition_release_not_found';
  end if;

  if not exists (
    select 1 from public.profiles as profile where profile.id = p_owner_profile_id
  ) then
    raise exception using errcode = '23503', message = 'owner_profile_not_found';
  end if;

  insert into public.courses (
    offering_key,
    course_definition_key,
    course_definition_release_id,
    code,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_offering_key,
    v_course_definition_key,
    p_course_definition_release_id,
    p_code,
    p_starts_at,
    p_ends_at,
    p_external_url
  )
  returning id into v_course_id;

  insert into public.course_memberships (course_id, profile_id, role, status)
  values (v_course_id, p_owner_profile_id, 'owner', 'active');

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    v_course_id,
    p_owner_profile_id,
    'created',
    'owner',
    'active',
    p_owner_profile_id,
    'initial course owner'
  );

  return v_course_id;
end
$function$;

alter function "private"."branch_course_offering"(text, uuid, text, uuid, timestamp with time zone, timestamp with time zone, text) owner to "ainigma_function_owner";

create or replace function private.can_view_profile (
  p_profile_id uuid
)
  returns boolean
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid;
begin
  if p_profile_id is null then
    return false;
  end if;

  v_profile_id := private.current_profile_id();

  if p_profile_id = v_profile_id then
    return true;
  end if;

  return exists (
    select 1
    from public.course_memberships as staff_membership
    join public.course_memberships as roster_membership
      on roster_membership.course_id = staff_membership.course_id
    where staff_membership.profile_id = v_profile_id
      and staff_membership.status = 'active'
      and staff_membership.role in ('owner', 'instructor')
      and roster_membership.profile_id = p_profile_id
  );
end
$function$;

alter function "private"."can_view_profile"(uuid) owner to "ainigma_function_owner";

create or replace function private.claim_course_repository_provisioning (
  p_limit      integer default 25,
  p_course_id  uuid    default null::uuid,
  p_profile_id uuid    default null::uuid
)
  returns table (
    course_id               uuid,
    profile_id              uuid,
    access_request_id       uuid,
    offering_key            text,
    provider_kind           text,
    external_group_id       text,
    external_group_handle   text,
    repository_name         text,
    external_repository_id  text,
    external_repository_url text,
    external_user_handle    text,
    external_user_id        text,
    lease_token             uuid,
    attempt_count           integer
  )
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'invalid_repository_claim_limit';
  end if;

  return query
  with candidates as (
    select
      repository.course_id,
      repository.profile_id,
      repository.access_request_id,
      course.offering_key,
      organization.provider_kind,
      repository.external_group_id,
      repository.external_group_handle,
      repository.external_repository_id,
      repository.external_repository_url,
      access_row.external_user_id,
      access_row.external_user_handle,
      case
        when access_row.external_user_handle is null then null
        when char_length('submissions-' || course.offering_key || '-' || access_row.external_user_handle) <= 100
          then 'submissions-' || course.offering_key || '-' || access_row.external_user_handle
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || access_row.external_user_handle), 8) || '-' ||
          left(access_row.external_user_handle, 20)
      end as generated_repository_name
    from private.course_repository_provisioning as repository
    join private.external_course_access as access_row
      on access_row.course_id = repository.course_id
     and access_row.profile_id = repository.profile_id
    join private.course_access_requests as request_row
      on request_row.id = repository.access_request_id
     and request_row.course_id = repository.course_id
     and request_row.requester_profile_id = repository.profile_id
    join public.course_memberships as membership
      on membership.course_id = repository.course_id
     and membership.profile_id = repository.profile_id
     and membership.created_from_access_request_id = repository.access_request_id
     and membership.status = 'active'
    join public.courses as course on course.id = repository.course_id
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = course.course_definition_key
    where request_row.status = 'approved'
      and access_row.state = 'active'
      and access_row.external_user_handle is not null
      and access_row.failure_code is null
      and access_row.last_checked_at >= clock_timestamp() - interval '5 minutes'
      and (p_course_id is null or repository.course_id = p_course_id)
      and (p_profile_id is null or repository.profile_id = p_profile_id)
      and (
        repository.state = 'queued'
        or (repository.state = 'retry_wait' and repository.next_attempt_at <= clock_timestamp())
        or (repository.state = 'provisioning' and repository.lease_expires_at <= clock_timestamp())
      )
    order by repository.updated_at, repository.created_at
    limit p_limit
    for update of repository skip locked
  ), claimed as (
    update private.course_repository_provisioning as repository
    set state = 'provisioning',
        lease_token = gen_random_uuid(),
        lease_expires_at = clock_timestamp() + interval '5 minutes',
        attempt_count = repository.attempt_count + 1,
        repository_name = coalesce(repository.repository_name, candidates.generated_repository_name),
        last_error = null,
        updated_at = clock_timestamp()
    from candidates
    where repository.course_id = candidates.course_id
      and repository.profile_id = candidates.profile_id
    returning repository.*
  )
  select
    claimed.course_id,
    claimed.profile_id,
    claimed.access_request_id,
    course.offering_key,
    organization.provider_kind,
    claimed.external_group_id,
    claimed.external_group_handle,
    claimed.repository_name,
    claimed.external_repository_id,
    claimed.external_repository_url,
    access_row.external_user_handle,
    access_row.external_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  join private.external_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
  ;
end
$function$;

alter function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) owner to "ainigma_function_owner";

create or replace function private.complete_course_repository_provisioning (
  p_course_id               uuid,
  p_profile_id              uuid,
  p_lease_token             uuid,
  p_external_repository_id  text,
  p_repository_name         text,
  p_external_repository_url text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_repository private.course_repository_provisioning%rowtype;
begin
  if p_external_repository_id is null
    or p_external_repository_id <> btrim(p_external_repository_id)
    or char_length(p_external_repository_id) not between 1 and 255
    or p_repository_name is null
    or p_repository_name <> btrim(p_repository_name)
    or char_length(p_repository_name) not between 1 and 100
    or p_external_repository_url is null
    or p_external_repository_url <> btrim(p_external_repository_url)
    or char_length(p_external_repository_url) not between 1 and 2048
  then
    raise exception using errcode = '22023', message = 'invalid_external_repository';
  end if;

  select repository.*
  into v_repository
  from private.course_repository_provisioning as repository
  where repository.course_id = p_course_id
    and repository.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'repository_provisioning_not_started';
  end if;

  if v_repository.state = 'ready' then
    if v_repository.external_repository_id = p_external_repository_id
      and v_repository.repository_name = p_repository_name
      and v_repository.external_repository_url = p_external_repository_url
    then
      return;
    end if;
    raise exception using errcode = '55000', message = 'repository_already_bound';
  end if;

  if v_repository.state <> 'provisioning'
    or v_repository.lease_token is distinct from p_lease_token
  then
    raise exception using errcode = '55000', message = 'repository_lease_invalid';
  end if;

  if v_repository.repository_name is distinct from p_repository_name then
    raise exception using errcode = '42501', message = 'repository_name_mismatch';
  end if;

  update private.course_repository_provisioning
  set state = 'ready',
      external_repository_id = p_external_repository_id,
      external_repository_url = p_external_repository_url,
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = null,
      last_error = null,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) owner to "ainigma_function_owner";

create or replace function private.confirm_external_course_access (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_external_group_id      text,
  p_external_group_handle  text,
  p_external_invitation_id text,
  p_external_user_id       text,
  p_external_user_handle   text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_provider_issuer text;
begin
  if p_external_group_id is null
    or p_external_group_id <> btrim(p_external_group_id)
    or char_length(p_external_group_id) not between 1 and 255
    or p_external_group_handle is null
    or p_external_group_handle <> btrim(p_external_group_handle)
    or char_length(p_external_group_handle) not between 1 and 255
    or p_external_invitation_id is null
    or p_external_invitation_id <> btrim(p_external_invitation_id)
    or char_length(p_external_invitation_id) not between 1 and 255
    or p_external_user_id is null
    or p_external_user_id <> btrim(p_external_user_id)
    or char_length(p_external_user_id) not between 1 and 255
    or p_external_user_handle is null
    or p_external_user_handle <> btrim(p_external_user_handle)
    or char_length(p_external_user_handle) not between 1 and 255
    or p_external_user_handle ~ '[[:space:]]'
  then
    raise exception using errcode = '22023', message = 'invalid_external_membership_identity';
  end if;

  select organization.external_group_id,
         organization.external_group_handle,
         organization.provider_issuer
  into v_expected_external_group_id,
       v_expected_external_group_handle,
       v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
  for update of course;

  if not found then
    raise exception using errcode = '55000', message = 'course_offering_not_reconcilable';
  end if;

  select access_row.* into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id and access_row.profile_id = p_profile_id
  for update;

  if not found then raise exception using errcode = '23503', message = 'external_access_not_started'; end if;

  select request_row.* into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id and request_row.status = 'approved';
  if not found then raise exception using errcode = '42501', message = 'course_access_not_approved'; end if;

  if p_external_group_id is distinct from v_expected_external_group_id
    or p_external_group_handle is distinct from v_expected_external_group_handle
  then
    raise exception using errcode = '42501', message = 'external_group_mismatch';
  end if;

  if v_access.external_invitation_id is distinct from p_external_invitation_id then
    raise exception using errcode = '42501', message = 'external_invitation_mismatch';
  end if;

  if not exists (
    select 1 from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = v_provider_issuer
      and identifier.normalized_value = p_external_user_id
      and identifier.revoked_at is null
  ) then
    raise exception using errcode = '42501', message = 'external_identity_mismatch';
  end if;

  update private.external_course_access
  set external_group_id = p_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      external_user_id = p_external_user_id,
      external_user_handle = p_external_user_handle,
      state = 'active',
      accepted_at = coalesce(accepted_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null,
      consecutive_membership_absences = 0
  where course_id = p_course_id and profile_id = p_profile_id;

  insert into public.course_memberships (
    course_id, profile_id, role, status, created_from_access_request_id
  ) values (
    p_course_id, p_profile_id, 'learner', 'active', v_request.id
  )
  on conflict (course_id, profile_id) do nothing;

  insert into private.course_membership_events (
    course_id, profile_id, event_kind, new_role, new_status, actor_profile_id, reason
  )
  select p_course_id, p_profile_id, 'created', 'learner', 'active', null,
    'GitHub organization invitation and membership confirmed'
  where not exists (
    select 1 from private.course_membership_events as event_row
    where event_row.course_id = p_course_id
      and event_row.profile_id = p_profile_id
      and event_row.event_kind = 'created'
      and event_row.new_role = 'learner'
      and event_row.new_status = 'active'
  );

end
$function$;

alter function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) owner to "ainigma_function_owner";

create or replace function private.current_profile_id()
  returns uuid
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_auth_user_id uuid := private.request_auth_user_id();
  v_profile_id uuid;
begin
  if v_auth_user_id is null then
    raise sqlstate 'PT401' using message = 'authentication_required';
  end if;

  select link.profile_id
  into v_profile_id
  from private.auth_user_links as link
  where link.auth_user_id = v_auth_user_id;

  if v_profile_id is null then
    raise sqlstate 'PT403' using message = 'profile_not_provisioned';
  end if;

  return v_profile_id;
end
$function$;

alter function "private"."current_profile_id"() owner to "ainigma_function_owner";

create or replace function private.ensure_auth_user_profile (
  p_auth_user_id uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid;
begin
  if p_auth_user_id is null then
    raise exception using errcode = '22004', message = 'auth_user_id_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_auth_user_id::text, 0)
  );

  perform 1
  from private.auth_users as auth_user
  where auth_user.id = p_auth_user_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_user_not_found';
  end if;

  select link.profile_id
  into v_profile_id
  from private.auth_user_links as link
  where link.auth_user_id = p_auth_user_id;

  if v_profile_id is not null then
    return v_profile_id;
  end if;

  insert into public.profiles default values
  returning id into v_profile_id;

  insert into private.auth_user_links (auth_user_id, profile_id)
  values (p_auth_user_id, v_profile_id);

  return v_profile_id;
end
$function$;

alter function "private"."ensure_auth_user_profile"(uuid) owner to "ainigma_function_owner";

create or replace function private.handle_auth_identity_changed()
  returns trigger
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
begin
  perform private.sync_auth_identity(new.id);
  return new;
end
$function$;

alter function "private"."handle_auth_identity_changed"() owner to "ainigma_function_owner";

create or replace function private.handle_auth_user_created()
  returns trigger
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
begin
  perform private.ensure_auth_user_profile(new.id);
  return new;
end
$function$;

alter function "private"."handle_auth_user_created"() owner to "ainigma_function_owner";

create or replace function private.has_course_role (
  p_course_id uuid,
  p_roles     private.course_membership_role[]
)
  returns boolean
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid;
begin
  if p_course_id is null or coalesce(cardinality(p_roles), 0) = 0 then
    return false;
  end if;

  v_profile_id := private.current_profile_id();

  return exists (
    select 1
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.profile_id = v_profile_id
      and membership.status = 'active'
      and membership.role = any (p_roles)
  );
end
$function$;

alter function "private"."has_course_role"(uuid, private.course_membership_role[]) owner to "ainigma_function_owner";

create or replace function private.list_external_course_access_to_reconcile()
  returns table (
    course_id                      uuid,
    profile_id                     uuid,
    access_request_id              uuid,
    offering_key                   text,
    provider_kind                  text,
    provider_issuer                text,
    expected_external_group_id     text,
    expected_external_group_handle text,
    external_user_id               text,
    external_user_handle           text,
    external_invitation_id         text,
    external_email                 text,
    invitation_method              text,
    invitation_target              text,
    state                          text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select access_row.course_id,
     access_row.profile_id,
     access_row.access_request_id,
     course.offering_key,
     organization.provider_kind,
     organization.provider_issuer,
     organization.external_group_id,
     organization.external_group_handle,
     access_row.external_user_id,
     access_row.external_user_handle,
     access_row.external_invitation_id,
     email.normalized_value,
     access_row.invitation_method,
     access_row.invitation_target,
     (access_row.state)::text
  AS state
    FROM ((((private.external_course_access access_row
      JOIN private.course_access_requests request_row ON (((request_row.id = access_row.access_request_id) AND (request_row.course_id = access_row.course_id) AND (request_row.requester_profile_id = access_row.profile_id))))
      JOIN public.courses course ON ((course.id = access_row.course_id)))
      JOIN private.course_definition_external_groups organization ON ((organization.course_definition_key = course.course_definition_key)))
      LEFT JOIN LATERAL ( SELECT identifier.normalized_value
            FROM private.profile_identifiers identifier
           WHERE ((identifier.profile_id = access_row.profile_id) AND (identifier.kind = 'email'::text) AND (identifier.issuer = organization.provider_issuer) AND (identifier.revoked_at IS NULL))
           ORDER BY identifier.last_verified_at DESC
          LIMIT 1) email ON (true))
   WHERE ((request_row.status = 'approved'::private.course_access_request_status) AND (course.status = 'published'::private.course_offering_status) AND (access_row.state <> 'revoked'::private.external_course_access_state));
END;

alter function "private"."list_external_course_access_to_reconcile"() owner to "ainigma_function_owner";

create or replace function private.reconcile_auth_identities()
  returns table (
    auth_identity_id uuid,
    status           text,
    detail           text
  )
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_identity_id uuid;
begin
  for v_identity_id in
    select identity_row.id
    from private.auth_identities as identity_row
    where identity_row.provider = 'github'
    order by identity_row.created_at, identity_row.id
  loop
    auth_identity_id := v_identity_id;

    begin
      perform private.sync_auth_identity(v_identity_id);
      status := 'synced';
      detail := null;
    exception when others then
      status := 'error';
      detail := sqlstate || ':' || sqlerrm;
    end;

    return next;
  end loop;
end
$function$;

alter function "private"."reconcile_auth_identities"() owner to "ainigma_function_owner";

create or replace function private.reconcile_auth_users()
  returns table (
    auth_user_id uuid,
    profile_id   uuid,
    action       text
  )
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_auth_user_id uuid;
begin
  for v_auth_user_id in
    select auth_user.id
    from private.auth_users as auth_user
    left join private.auth_user_links as link
      on link.auth_user_id = auth_user.id
    where link.auth_user_id is null
      and auth_user.deleted_at is null
    order by auth_user.created_at, auth_user.id
  loop
    auth_user_id := v_auth_user_id;
    profile_id := private.ensure_auth_user_profile(v_auth_user_id);
    action := 'created_profile_link';
    return next;
  end loop;
end
$function$;

alter function "private"."reconcile_auth_users"() owner to "ainigma_function_owner";

create or replace function private.record_course_repository_provisioning_failure (
  p_course_id   uuid,
  p_profile_id  uuid,
  p_lease_token uuid,
  p_error_code  text,
  p_retryable   boolean
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_repository private.course_repository_provisioning%rowtype;
  v_retry_after_seconds integer;
begin
  if p_error_code is null
    or p_error_code <> btrim(p_error_code)
    or char_length(p_error_code) not between 1 and 255
    or p_retryable is null
  then
    raise exception using errcode = '22023', message = 'invalid_repository_failure';
  end if;

  select repository.*
  into v_repository
  from private.course_repository_provisioning as repository
  where repository.course_id = p_course_id
    and repository.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'repository_provisioning_not_started';
  end if;

  if v_repository.state in ('retry_wait', 'blocked')
    and v_repository.last_error = p_error_code
  then
    return;
  end if;

  if v_repository.state <> 'provisioning'
    or v_repository.lease_token is distinct from p_lease_token
  then
    raise exception using errcode = '55000', message = 'repository_lease_invalid';
  end if;

  v_retry_after_seconds := least(
    3600,
    30 * (2 ^ least(greatest(v_repository.attempt_count - 1, 0), 7))::integer
  );

  update private.course_repository_provisioning
  set state = case
        when p_retryable and v_repository.attempt_count < 8 then 'retry_wait'
        else 'blocked'
      end,
      lease_token = null,
      lease_expires_at = null,
      next_attempt_at = case
        when p_retryable and v_repository.attempt_count < 8
          then clock_timestamp() + make_interval(secs => v_retry_after_seconds)
        else null
      end,
      last_error = p_error_code,
      updated_at = clock_timestamp()
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_check_failure (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_failure_code text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_failure_code text := nullif(btrim(p_failure_code), '');
begin
  if v_failure_code is null or char_length(v_failure_code) > 255 then
    raise exception using errcode = '22023', message = 'invalid_external_access_failure_code';
  end if;

  update private.external_course_access as access_row
  set last_checked_at = clock_timestamp(),
      failure_code = v_failure_code
  from private.course_access_requests as request_row,
       public.courses as course
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
    and request_row.id = access_row.access_request_id
    and request_row.course_id = access_row.course_id
    and request_row.requester_profile_id = access_row.profile_id
    and request_row.status = 'approved'
    and course.id = access_row.course_id
    and course.status = 'published'
    and access_row.state <> 'revoked';

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_reconcilable';
  end if;
end
$function$;

alter function "private"."record_external_course_access_check_failure"(uuid, uuid, text) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_invitation (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_invitation_method      text,
  p_invitation_target      text,
  p_external_invitation_id text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_email_domain text;
  v_email_domain_enforced boolean;
  v_email_domain_allowed boolean;
begin
  if p_invitation_method not in ('email', 'external_user_id')
    or p_invitation_target is null
    or p_invitation_target <> btrim(p_invitation_target)
    or char_length(p_invitation_target) not between 1 and 512
    or p_external_invitation_id is null
    or p_external_invitation_id <> btrim(p_external_invitation_id)
    or char_length(p_external_invitation_id) not between 1 and 255
  then
    raise exception using errcode = '22023', message = 'invalid_external_invitation_target';
  end if;

  if p_invitation_method = 'email' then
    p_invitation_target := lower(p_invitation_target);
    v_email_domain := split_part(p_invitation_target, '@', 2);
    if p_invitation_target !~ '^[^@[:space:]]+@[^@[:space:]]+$'
      or v_email_domain ~ '(^[.]|[.]$|[.][.])' then
      raise exception using errcode = '22023', message = 'email_domain_not_allowed';
    end if;

    select organization.email_domain_enforced,
           exists (
             select 1
             from private.course_definition_external_email_domains as domain
             where domain.course_definition_key = organization.course_definition_key
               and (v_email_domain = domain.domain_suffix
                 or v_email_domain like '%.' || domain.domain_suffix)
           )
    into v_email_domain_enforced, v_email_domain_allowed
    from public.courses as course
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = course.course_definition_key
    where course.id = p_course_id;

    if coalesce(v_email_domain_enforced, true)
      and not coalesce(v_email_domain_allowed, false) then
      raise exception using errcode = '22023', message = 'email_domain_not_allowed';
    end if;
  end if;

  select access_row.*
  into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_started';
  end if;

  perform 1
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id
    and request_row.course_id = p_course_id
    and request_row.requester_profile_id = p_profile_id
    and request_row.status = 'approved';

  if not found then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  if p_invitation_method <> 'email' then
    v_expected_target := v_access.external_user_id;
    if v_expected_target is null or v_expected_target <> p_invitation_target then
      raise exception using errcode = '42501', message = 'external_invitation_identity_mismatch';
    end if;
  end if;

  select organization.external_group_id, organization.external_group_handle
  into v_expected_external_group_id, v_expected_external_group_handle
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'external_group_not_configured';
  end if;

  if v_access.state = 'active' then
    return;
  end if;

  if v_access.state = 'invitation_pending'
    and v_access.external_invitation_id = p_external_invitation_id
    and v_access.invitation_method = p_invitation_method
    and v_access.invitation_target = p_invitation_target
  then
    return;
  end if;

  update private.external_course_access
  set external_group_id = v_expected_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      external_invitation_id = p_external_invitation_id,
      invitation_method = p_invitation_method,
      invitation_target = p_invitation_target,
      state = 'invitation_pending',
      invited_at = case
        when external_invitation_id is distinct from p_external_invitation_id
          then clock_timestamp()
        else coalesce(invited_at, clock_timestamp())
      end,
      accepted_at = null,
      last_checked_at = clock_timestamp(),
      failure_code = null,
      consecutive_membership_absences = 0
  where course_id = p_course_id and profile_id = p_profile_id;
end
$function$;

alter function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_membership_absence (
  p_course_id  uuid,
  p_profile_id uuid
)
  returns boolean
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_absence_count integer;
begin
  perform 1
  from public.courses as course
  where course.id = p_course_id
    and course.status = 'published'
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'published_course_not_found';
  end if;

  update private.external_course_access as access_row
  set consecutive_membership_absences = access_row.consecutive_membership_absences + 1,
      last_checked_at = clock_timestamp(),
      failure_code = 'external_membership_temporarily_missing'
  from private.course_access_requests as request_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
    and access_row.state = 'active'
    and request_row.id = access_row.access_request_id
    and request_row.course_id = access_row.course_id
    and request_row.requester_profile_id = access_row.profile_id
    and request_row.status = 'approved'
  returning access_row.consecutive_membership_absences into v_absence_count;

  if not found then
    raise exception using errcode = '23503', message = 'active_external_access_not_reconcilable';
  end if;

  if v_absence_count < 3 then
    return false;
  end if;

  perform private.record_external_course_access_status(
    p_course_id,
    p_profile_id,
    'revoked',
    null
  );
  return true;
end
$function$;

alter function "private"."record_external_course_access_membership_absence"(uuid, uuid) owner to "ainigma_function_owner";

create or replace function private.record_external_course_access_status (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_state        private.external_course_access_state,
  p_failure_code text                                 default null::text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_failure_code text := nullif(btrim(p_failure_code), '');
begin
  if p_state not in ('invitation_pending', 'sso_required', 'failed', 'revoked') then
    raise exception using errcode = '22023', message = 'invalid_external_course_access_state';
  end if;

  if p_state = 'failed' and v_failure_code is null then
    raise exception using errcode = '22023', message = 'external_access_failure_code_required';
  end if;

  perform 1
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select access_row.*
  into v_access
  from private.external_course_access as access_row
  where access_row.course_id = p_course_id
    and access_row.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'external_access_not_started';
  end if;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id
    and request_row.course_id = p_course_id
    and request_row.requester_profile_id = p_profile_id
    and request_row.status = 'approved';

  if not found then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  select organization.external_group_id, organization.external_group_handle
  into v_expected_external_group_id, v_expected_external_group_handle
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found then
    raise exception using errcode = '23503', message = 'external_group_not_configured';
  end if;

  if v_access.state = 'active' and p_state <> 'revoked' then
    raise exception using errcode = '55000', message = 'active_external_access_requires_confirmation';
  end if;

  if v_access.state = p_state and v_access.failure_code is not distinct from v_failure_code then
    update private.external_course_access
    set last_checked_at = clock_timestamp()
    where course_id = p_course_id and profile_id = p_profile_id;
    return;
  end if;

  update private.external_course_access
  set external_group_id = v_expected_external_group_id,
      external_group_handle = v_expected_external_group_handle,
      state = p_state,
      invited_at = case
        when p_state in ('invitation_pending', 'sso_required') then coalesce(invited_at, clock_timestamp())
        else invited_at
      end,
      last_checked_at = clock_timestamp(),
      failure_code = v_failure_code
  where course_id = p_course_id and profile_id = p_profile_id;

  if p_state = 'revoked' then
    update public.course_memberships
    set status = 'revoked',
        revoked_at = coalesce(revoked_at, clock_timestamp()),
        suspended_at = null
    where course_id = p_course_id
      and profile_id = p_profile_id
      and created_from_access_request_id = v_request.id
      and status = 'active';

    insert into private.course_membership_events (
      course_id, profile_id, event_kind, previous_role, previous_status,
      new_role, new_status, actor_profile_id, reason
    )
    select
      p_course_id, p_profile_id, 'transitioned', membership.role, 'active',
      membership.role, 'revoked', null,
      'GitHub course organization membership no longer active'
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.profile_id = p_profile_id
      and membership.created_from_access_request_id = v_request.id
      and membership.status = 'revoked'
      and membership.revoked_at is not null
      and not exists (
        select 1
        from private.course_membership_events as event_row
        where event_row.course_id = p_course_id
          and event_row.profile_id = p_profile_id
          and event_row.event_kind = 'transitioned'
          and event_row.new_status = 'revoked'
          and event_row.reason = 'GitHub course organization membership no longer active'
      );
  end if;
end
$function$;

alter function "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text) owner to "ainigma_function_owner";

create or replace function private.register_course_definition_release (
  p_course_definition_key text,
  p_source_commit_sha     text,
  p_course_release_digest text,
  p_artifact_ref          text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_release private.course_definition_releases%rowtype;
begin
  insert into private.course_definition_releases (
    course_definition_key,
    source_commit_sha,
    course_release_digest,
    artifact_ref
  )
  values (
    p_course_definition_key,
    p_source_commit_sha,
    p_course_release_digest,
    p_artifact_ref
  )
  on conflict (course_definition_key, course_release_digest) do nothing
  returning * into v_release;

  if v_release.id is null then
    select release.*
    into strict v_release
    from private.course_definition_releases as release
    where release.course_definition_key = p_course_definition_key
      and release.course_release_digest = p_course_release_digest;

    if v_release.source_commit_sha <> p_source_commit_sha
      or v_release.artifact_ref <> p_artifact_ref
    then
      raise exception using
        errcode = '23505',
        message = 'course_definition_release_metadata_mismatch';
    end if;
  end if;

  return v_release.id;
end
$function$;

alter function "private"."register_course_definition_release"(text, text, text, text) owner to "ainigma_function_owner";

create or replace function private.reject_mutation()
  returns trigger
  language plpgsql
  set search_path to ''
  AS $function$
begin
  raise exception using
    errcode = '55000',
    message = format('%I.%I is append-only', tg_table_schema, tg_table_name);
end
$function$;

create or replace function private.request_auth_user_id()
  returns uuid
  language sql
  stable
  set search_path to ''
BEGIN ATOMIC
 select auth.uid()
  AS uid;
END;

create or replace function private.set_updated_at()
  returns trigger
  language plpgsql
  set search_path to ''
  AS $function$
begin
  new.updated_at := clock_timestamp();
  return new;
end
$function$;

create or replace function private.sync_auth_identity (
  p_identity_id uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_identity record;
  v_profile_id uuid;
  v_username text;
  v_email text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_identity_id::text, 0)
  );

  select identity_row.*
  into v_identity
  from private.auth_identities as identity_row
  where identity_row.id = p_identity_id;

  if not found then
    raise exception using errcode = '23503', message = 'auth_identity_not_found';
  end if;

  v_profile_id := private.ensure_auth_user_profile(v_identity.user_id);

  if v_identity.provider <> 'github' then
    return v_profile_id;
  end if;

  if v_identity.provider_id !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'invalid_github_numeric_subject';
  end if;

  perform private.upsert_verified_identifier(
    v_profile_id,
    'external_user_id',
    'github.com',
    1,
    v_identity.provider_id,
    coalesce(v_identity.created_at, clock_timestamp()),
    v_identity.user_id,
    v_identity.id::text
  );

  v_username := lower(btrim(coalesce(
    v_identity.identity_data ->> 'user_name',
    v_identity.identity_data ->> 'preferred_username',
    v_identity.identity_data ->> 'login'
  )));

  if nullif(v_username, '') is not null then
    update private.profile_identifiers
    set revoked_at = clock_timestamp(),
        last_verified_at = clock_timestamp()
    where profile_id = v_profile_id
      and kind = 'external_user_handle'
      and issuer = 'github.com'
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'external_user_handle',
      'github.com',
      1,
      v_username,
      coalesce(v_identity.created_at, clock_timestamp()),
      v_identity.user_id,
      v_identity.id::text
    );
  end if;

  if lower(coalesce(v_identity.identity_data ->> 'email_verified', 'false')) = 'true' then
    v_email := lower(btrim(v_identity.identity_data ->> 'email'));

    if nullif(v_email, '') is not null then
      update private.profile_identifiers
      set revoked_at = clock_timestamp(),
          last_verified_at = clock_timestamp()
      where profile_id = v_profile_id
        and kind = 'email'
        and issuer = 'github.com'
        and scheme_version = 1
        and normalized_value <> v_email
        and revoked_at is null;

      perform private.upsert_verified_identifier(
        v_profile_id,
        'email',
        'github.com',
        1,
        v_email,
        coalesce(v_identity.created_at, clock_timestamp()),
        v_identity.user_id,
        v_identity.id::text
      );
    end if;
  end if;

  return v_profile_id;
end
$function$;

alter function "private"."sync_auth_identity"(uuid) owner to "ainigma_function_owner";

create or replace function private.transfer_course_ownership (
  p_course_id            uuid,
  p_new_owner_profile_id uuid,
  p_actor_profile_id     uuid,
  p_reason               text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_current_owner_profile_id uuid;
  v_target_membership public.course_memberships%rowtype;
begin
  if p_course_id is null or p_new_owner_profile_id is null or p_actor_profile_id is null then
    raise exception using errcode = '22004', message = 'course_ownership_transfer_arguments_required';
  end if;

  if p_reason is null or p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_course_membership_reason';
  end if;

  -- All membership mutations lock the course row, so ownership changes are
  -- serialized with staff and learner membership changes.
  perform 1
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.profile_id
  into v_current_owner_profile_id
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.role = 'owner'
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23514', message = 'course_requires_active_owner';
  end if;

  if p_actor_profile_id <> v_current_owner_profile_id then
    raise exception using errcode = '42501', message = 'course_owner_required';
  end if;

  if p_new_owner_profile_id = v_current_owner_profile_id then
    return;
  end if;

  select membership.*
  into v_target_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_new_owner_profile_id
    and membership.status = 'active'
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_owner_target_membership_not_found';
  end if;

  if v_target_membership.role <> 'instructor' then
    raise exception using errcode = '42501', message = 'course_owner_target_must_be_instructor';
  end if;

  -- Demote first so the partial unique index can enforce one active owner
  -- throughout the transaction, then promote the selected instructor.
  update public.course_memberships
  set role = 'instructor'
  where course_id = p_course_id
    and profile_id = v_current_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_current_owner_profile_id,
    'transitioned',
    'owner',
    'active',
    'instructor',
    'active',
    p_actor_profile_id,
    p_reason
  );

  update public.course_memberships
  set role = 'owner'
  where course_id = p_course_id
    and profile_id = p_new_owner_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    v_target_membership.profile_id,
    'transitioned',
    v_target_membership.role,
    v_target_membership.status,
    'owner',
    'active',
    p_actor_profile_id,
    p_reason
  );
end
$function$;

alter function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) owner to "ainigma_function_owner";

create or replace function private.transition_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_new_role         private.course_membership_role,
  p_new_status       private.course_membership_status,
  p_actor_profile_id uuid,
  p_reason           text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_membership public.course_memberships%rowtype;
  v_actor_role private.course_membership_role;
  v_active_owner_count integer;
begin
  if p_new_role is null or p_new_role not in ('owner', 'instructor', 'learner') then
    raise exception using errcode = '22023', message = 'invalid_course_membership_role';
  end if;

  if p_new_role = 'owner' then
    raise exception using errcode = '42501', message = 'course_owner_transfer_required';
  end if;

  perform 1 from public.courses as course where course.id = p_course_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  select membership.role
  into v_actor_role
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_actor_profile_id
    and membership.status = 'active'
  for share;

  if v_actor_role is null
    or (
      p_new_role in ('owner', 'instructor')
      and v_actor_role <> 'owner'
    )
    or (
      p_new_role = 'learner'
      and v_actor_role not in ('owner', 'instructor')
    )
  then
    raise exception using errcode = '42501', message = 'course_membership_admin_required';
  end if;

  select membership.*
  into v_membership
  from public.course_memberships as membership
  where membership.course_id = p_course_id
    and membership.profile_id = p_profile_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_membership_not_found';
  end if;

  if v_actor_role = 'instructor' and v_membership.role <> 'learner' then
    raise exception using errcode = '42501', message = 'course_staff_admin_required';
  end if;

  if v_membership.role = p_new_role and v_membership.status = p_new_status then
    return;
  end if;

  if v_membership.role = 'owner'
    and v_membership.status = 'active'
    and (p_new_role <> 'owner' or p_new_status <> 'active')
  then
    select count(*)
    into v_active_owner_count
    from public.course_memberships as membership
    where membership.course_id = p_course_id
      and membership.role = 'owner'
      and membership.status = 'active';

    if v_active_owner_count <= 1 then
      raise exception using errcode = '23514', message = 'course_requires_active_owner';
    end if;
  end if;

  update public.course_memberships
  set role = p_new_role,
      status = p_new_status,
      suspended_at = case when p_new_status = 'suspended' then clock_timestamp() else null end,
      revoked_at = case when p_new_status = 'revoked' then clock_timestamp() else null end
  where course_id = p_course_id
    and profile_id = p_profile_id;

  insert into private.course_membership_events (
    course_id,
    profile_id,
    event_kind,
    previous_role,
    previous_status,
    new_role,
    new_status,
    actor_profile_id,
    reason
  )
  values (
    p_course_id,
    p_profile_id,
    'transitioned',
    v_membership.role,
    v_membership.status,
    p_new_role,
    p_new_status,
    p_actor_profile_id,
    p_reason
  );
end
$function$;

alter function "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) owner to "ainigma_function_owner";

create or replace function private.upsert_verified_identifier (
  p_profile_id           uuid,
  p_kind                 text,
  p_issuer               text,
  p_scheme_version       integer,
  p_normalized_value     text,
  p_verified_at          timestamp with time zone,
  p_source_auth_user_id  uuid,
  p_provider_identity_id text
)
  returns uuid
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_identifier_id uuid;
  v_existing_profile_id uuid;
begin
  if p_kind = 'external_user_id'
    and exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.profile_id = p_profile_id
        and identifier.kind = p_kind
        and identifier.issuer = p_issuer
        and identifier.scheme_version = p_scheme_version
        and identifier.normalized_value <> p_normalized_value
        and identifier.revoked_at is null
    )
  then
    raise exception using errcode = '23505', message = 'verified_identifier_conflict';
  end if;

  select identifier.id, identifier.profile_id
  into v_identifier_id, v_existing_profile_id
  from private.profile_identifiers as identifier
  where identifier.kind = p_kind
    and identifier.issuer = p_issuer
    and identifier.scheme_version = p_scheme_version
    and identifier.normalized_value = p_normalized_value
    and identifier.revoked_at is null
  for update;

  if v_identifier_id is not null then
    if v_existing_profile_id <> p_profile_id then
      raise exception using errcode = '23505', message = 'verified_identifier_conflict';
    end if;

    update private.profile_identifiers
    set last_verified_at = clock_timestamp(),
        source_auth_user_id = p_source_auth_user_id,
        provider_identity_id = p_provider_identity_id
    where id = v_identifier_id;

    return v_identifier_id;
  end if;

  insert into private.profile_identifiers (
    profile_id,
    kind,
    issuer,
    scheme_version,
    normalized_value,
    verified_at,
    last_verified_at,
    source_auth_user_id,
    provider_identity_id
  )
  values (
    p_profile_id,
    p_kind,
    p_issuer,
    p_scheme_version,
    p_normalized_value,
    p_verified_at,
    clock_timestamp(),
    p_source_auth_user_id,
    p_provider_identity_id
  )
  returning id into v_identifier_id;

  return v_identifier_id;
end
$function$;

alter function "private"."upsert_verified_identifier"(uuid, text, text, integer, text, timestamp with time zone, uuid, text) owner to "ainigma_function_owner";

create or replace function public.approve_course_access_requests (
  p_offering_key text,
  p_request_ids  uuid[] default null::uuid[]
)
  returns integer
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
  v_provider_issuer text;
begin
  select course.id, organization.provider_issuer
  into v_course_id, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::private.course_membership_role[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if p_request_ids is not null and exists (
    select 1 from private.course_access_requests as request_row
    where request_row.id = any (p_request_ids) and request_row.course_id <> v_course_id
  ) then
    raise sqlstate 'PT400' using message = 'request_course_mismatch';
  end if;

  if exists (
    select 1
    from private.course_access_requests as request_row
    where request_row.course_id = v_course_id
      and request_row.status = 'pending'
      and (p_request_ids is null or request_row.id = any (p_request_ids))
      and not exists (
        select 1 from private.profile_identifiers as identifier
        where identifier.profile_id = request_row.requester_profile_id
          and identifier.kind = 'external_user_id'
          and identifier.issuer = v_provider_issuer
          and identifier.revoked_at is null
      )
  ) then
    raise sqlstate 'PT403' using message = 'external_identity_not_provisioned';
  end if;

  with selected as (
    select request_row.id
    from private.course_access_requests as request_row
    where request_row.course_id = v_course_id
      and request_row.status = 'pending'
      and (p_request_ids is null or request_row.id = any (p_request_ids))
    for update
  ), changed as (
    update private.course_access_requests as request_row
    set status = 'approved', decided_at = clock_timestamp(), decided_by = v_actor_profile_id
    from selected
    where request_row.id = selected.id
    returning request_row.*
  )
  insert into private.external_course_access (course_id, profile_id, access_request_id, external_user_id, state)
  select changed.course_id, changed.requester_profile_id, changed.id, identifier.normalized_value, 'not_started'
  from changed
  join private.profile_identifiers as identifier
    on identifier.profile_id = changed.requester_profile_id
   and identifier.kind = 'external_user_id'
   and identifier.issuer = v_provider_issuer
   and identifier.revoked_at is null
  on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

alter function "public"."approve_course_access_requests"(text, uuid[]) owner to "ainigma_function_owner";

create or replace function public.get_my_course_repository (
  p_offering_key text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_repository private.course_repository_provisioning%rowtype;
begin
  select course.id
  into v_course_id
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  where course.offering_key = p_offering_key
    and course.status in ('published', 'archived');

  if v_course_id is null then
    raise sqlstate 'PT404' using message = 'course_membership_not_found';
  end if;

  select repository.*
  into v_repository
  from private.course_repository_provisioning as repository
  where repository.course_id = v_course_id
    and repository.profile_id = v_profile_id;

  if not found then
    return jsonb_build_object(
      'offering_key', p_offering_key,
      'state', 'not_requested'
    );
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'offering_key', p_offering_key,
    'state', v_repository.state,
    'repository_name', v_repository.repository_name,
    'repository_url', v_repository.external_repository_url,
    'failure_code', v_repository.last_error,
    'requested_at', v_repository.created_at,
    'updated_at', v_repository.updated_at
  ));
end
$function$;

alter function "public"."get_my_course_repository"(text) owner to "ainigma_function_owner";

create or replace function public.get_my_profile()
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select profile.display_name,
     profile.created_at,
     profile.updated_at
    from public.profiles profile
   where (profile.id = private.current_profile_id());
end;

alter function "public"."get_my_profile"() owner to "ainigma_function_owner";

create or replace function public.list_available_courses()
  returns table (
    offering_key                 text,
    course_definition_key        text,
    course_definition_release_id uuid,
    code                         text,
    enrollment_mode              text,
    starts_at                    timestamp with time zone,
    ends_at                      timestamp with time zone,
    external_url                 text
  )
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select
    course.offering_key,
    course.course_definition_key,
    course.course_definition_release_id,
    course.code,
    course.enrollment_mode::text,
    course.starts_at,
    course.ends_at,
    course.external_url
  from public.courses as course
  where course.status = 'published';
$function$;

alter function "public"."list_available_courses"() owner to "ainigma_function_owner";

create or replace function public.list_course_access_requests (
  p_offering_key         text,
  p_status               private.course_access_request_status default 'pending'::private.course_access_request_status,
  p_authorization_filter text                                 default null::text
)
  returns table (
    request_id            uuid,
    offering_key          text,
    display_name          text,
    external_user_handle  text,
    verified_email        text,
    reason                text,
    status                private.course_access_request_status,
    authorization_status  text,
    requested_at          timestamp with time zone,
    decided_at            timestamp with time zone,
    external_access_state text
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_provider_issuer text;
begin
  select course.id, organization.provider_issuer
  into v_course_id, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key;

  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::private.course_membership_role[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    request_row.id,
    course.offering_key,
    profile.display_name,
    (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = request_row.requester_profile_id
        and identifier.kind = 'external_user_handle'
        and identifier.issuer = v_provider_issuer
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ),
    (
      select identifier.normalized_value
      from private.profile_identifiers as identifier
      where identifier.profile_id = request_row.requester_profile_id
        and identifier.kind = 'email'
        and identifier.revoked_at is null
      order by identifier.last_verified_at desc
      limit 1
    ),
    request_row.reason,
    request_row.status,
    case
      when exists (
        select 1
        from private.course_roster_allowlist as allowlist
        join private.profile_identifiers as identifier
          on identifier.kind = allowlist.identifier_kind
         and identifier.issuer = allowlist.identifier_issuer
         and identifier.scheme_version = allowlist.identifier_scheme_version
         and identifier.normalized_value = allowlist.normalized_identifier_value
         and identifier.profile_id = request_row.requester_profile_id
         and identifier.revoked_at is null
        where allowlist.course_id = v_course_id
          and allowlist.status = 'active'
      ) then 'preauthorized'
      when exists (
        select 1 from private.profile_identifiers as identifier
        where identifier.profile_id = request_row.requester_profile_id
          and identifier.revoked_at is null
      ) then 'not_preauthorized'
      else 'unverified'
    end,
    request_row.requested_at,
    request_row.decided_at,
    access_row.state::text
  from private.course_access_requests as request_row
  join public.courses as course on course.id = request_row.course_id
  join public.profiles as profile on profile.id = request_row.requester_profile_id
  left join private.external_course_access as access_row on access_row.access_request_id = request_row.id
  where request_row.course_id = v_course_id
    and (p_status is null or request_row.status = p_status)
    and (
      p_authorization_filter is null
      or p_authorization_filter = case
        when exists (
          select 1
          from private.course_roster_allowlist as allowlist
          join private.profile_identifiers as identifier
            on identifier.kind = allowlist.identifier_kind
           and identifier.issuer = allowlist.identifier_issuer
           and identifier.scheme_version = allowlist.identifier_scheme_version
           and identifier.normalized_value = allowlist.normalized_identifier_value
           and identifier.profile_id = request_row.requester_profile_id
           and identifier.revoked_at is null
          where allowlist.course_id = v_course_id and allowlist.status = 'active'
        ) then 'preauthorized'
        when exists (
          select 1 from private.profile_identifiers as identifier
          where identifier.profile_id = request_row.requester_profile_id
            and identifier.revoked_at is null
        ) then 'not_preauthorized'
        else 'unverified'
      end
    )
  order by request_row.requested_at;
end
$function$;

alter function "public"."list_course_access_requests"(text, private.course_access_request_status, text) owner to "ainigma_function_owner";

create or replace function public.list_course_roster (
  p_offering_key text
)
  returns table (
    display_name text,
    role         private.course_membership_role,
    status       private.course_membership_status,
    created_at   timestamp with time zone,
    suspended_at timestamp with time zone,
    revoked_at   timestamp with time zone
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
begin
  select course.id
  into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key;

  if v_course_id is null
    or not private.has_course_role(v_course_id, array['owner', 'instructor']::private.course_membership_role[])
  then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  return query
  select
    profile.display_name,
    membership.role,
    membership.status,
    membership.created_at,
    membership.suspended_at,
    membership.revoked_at
  from public.course_memberships as membership
  join public.profiles as profile
    on profile.id = membership.profile_id
  where membership.course_id = v_course_id
  order by membership.created_at, profile.id;
end
$function$;

alter function "public"."list_course_roster"(text) owner to "ainigma_function_owner";

create or replace function public.list_my_course_access_requests()
  returns table (
    offering_key          text,
    request_id            uuid,
    status                private.course_access_request_status,
    reason                text,
    requested_at          timestamp with time zone,
    decided_at            timestamp with time zone,
    external_access_state text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select course.offering_key,
     request_row.id,
     request_row.status,
     request_row.reason,
     request_row.requested_at,
     request_row.decided_at,
     (access_row.state)::text
  AS state
    FROM ((private.course_access_requests request_row
      JOIN public.courses course ON ((course.id = request_row.course_id)))
      LEFT JOIN private.external_course_access access_row ON ((access_row.access_request_id = request_row.id)))
   WHERE (request_row.requester_profile_id = private.current_profile_id())
   ORDER BY request_row.requested_at DESC;
END;

alter function "public"."list_my_course_access_requests"() owner to "ainigma_function_owner";

create or replace function public.list_my_courses()
  returns jsonb
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select
   jsonb_build_object('courses', COALESCE(( select jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_key', course.course_definition_key,
   'course_definition_release_id',
   course.course_definition_release_id,
   'code',
   course.code,
   'course_status',
   course.status,
   'membership_role',
   membership.role,
   'membership_status',
   membership.status,
   'starts_at',
   course.starts_at,
   'ends_at', course.ends_at, 'external_url', course.external_url, 'created_at', course.created_at, 'updated_at', course.updated_at) ORDER by course.offering_key) as jsonb_agg
            from (public.courses course
              JOIN public.course_memberships membership on ((membership.course_id = course.id)))
           where
             ((membership.profile_id = private.current_profile_id()) AND (membership.status = 'active'::private.course_membership_status) AND ((course.status = ANY
             (ARRAY['published'::private.course_offering_status, 'archived'::private.course_offering_status])) or
             ((course.status = 'draft'::private.course_offering_status) AND (membership.role = ANY (ARRAY['owner'::private.course_membership_role,
             'instructor'::private.course_membership_role])))))),
             '[]'::jsonb),
             'inactive_memberships',
             COALESCE(( select jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_release_id', course.course_definition_release_id,
             'course_status',
             course.status,
             'membership_role',
             membership.role,
             'membership_status',
             membership.status,
             'created_at', membership.created_at, 'suspended_at', membership.suspended_at, 'revoked_at', membership.revoked_at) ORDER by course.offering_key) as jsonb_agg
            from (public.courses course
              JOIN public.course_memberships membership on ((membership.course_id = course.id)))
           where
             ((membership.profile_id = private.current_profile_id()) AND (not ((membership.status = 'active'::private.course_membership_status) AND ((course.status = ANY
             (ARRAY['published'::private.course_offering_status, 'archived'::private.course_offering_status])) or
             ((course.status = 'draft'::private.course_offering_status) AND (membership.role = ANY (ARRAY['owner'::private.course_membership_role,
             'instructor'::private.course_membership_role])))))))), '[]'::jsonb))
  AS jsonb_build_object;
END;

alter function "public"."list_my_courses"() owner to "ainigma_function_owner";

create or replace function public.reject_course_access_requests (
  p_offering_key    text,
  p_request_ids     uuid[] default null::uuid[],
  p_decision_reason text   default null::text
)
  returns integer
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
begin
  select course.id into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::private.course_membership_role[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  update private.course_access_requests as request_row
  set status = 'rejected', decided_at = clock_timestamp(), decided_by = v_actor_profile_id,
      decision_reason = nullif(btrim(p_decision_reason), '')
  where request_row.course_id = v_course_id
    and request_row.status = 'pending'
    and (p_request_ids is null or request_row.id = any (p_request_ids));

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

alter function "public"."reject_course_access_requests"(text, uuid[], text) owner to "ainigma_function_owner";

create or replace function public.request_course_access (
  p_offering_key text,
  p_reason       text default null::text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_enrollment_mode text;
  v_provider_issuer text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id, course.enrollment_mode::text, organization.provider_issuer
  into v_course_id, v_enrollment_mode, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published';

  if v_course_id is null then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if v_enrollment_mode = 'closed' then
    raise sqlstate 'PT403' using message = 'course_enrollment_closed';
  end if;

  select membership.*
  into v_membership
  from public.course_memberships as membership
  where membership.course_id = v_course_id
    and membership.profile_id = v_profile_id;

  if found and v_membership.status = 'active' then
    return jsonb_build_object('state', 'active', 'offering_key', p_offering_key);
  end if;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.course_id = v_course_id
    and request_row.requester_profile_id = v_profile_id
  order by request_row.requested_at desc
  limit 1;

  if found and v_request.status in ('pending', 'approved') then
    return jsonb_build_object(
      'state', case when v_request.status = 'approved' then 'awaiting_external_access' else 'pending' end,
      'offering_key', p_offering_key,
      'request_id', v_request.id
    );
  end if;

  select
    v_enrollment_mode = 'allowlist_auto'
    and exists (
      select 1
      from private.course_roster_allowlist as allowlist
      join private.profile_identifiers as identifier
        on identifier.kind = allowlist.identifier_kind
       and identifier.issuer = allowlist.identifier_issuer
       and identifier.scheme_version = allowlist.identifier_scheme_version
       and identifier.normalized_value = allowlist.normalized_identifier_value
       and identifier.profile_id = v_profile_id
       and identifier.revoked_at is null
      where allowlist.course_id = v_course_id and allowlist.status = 'active'
    )
    and exists (
      select 1
      from private.profile_identifiers as identifier
      where identifier.profile_id = v_profile_id
        and identifier.kind = 'external_user_id'
        and identifier.issuer = v_provider_issuer
        and identifier.revoked_at is null
    )
  into v_auto_approved;

  insert into private.course_access_requests (
    course_id,
    requester_profile_id,
    reason,
    status,
    decision_source,
    decided_at
  )
  values (
    v_course_id,
    v_profile_id,
    nullif(btrim(p_reason), ''),
    case when v_auto_approved then 'approved'::private.course_access_request_status
         else 'pending'::private.course_access_request_status end,
    case when v_auto_approved then 'allowlist' else 'owner' end,
    case when v_auto_approved then clock_timestamp() else null end
  )
  returning * into v_request;

  if v_auto_approved then
    insert into private.external_course_access (
      course_id, profile_id, access_request_id, external_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      identifier.normalized_value,
      'not_started'
    from private.profile_identifiers as identifier
    where identifier.profile_id = v_profile_id
      and identifier.kind = 'external_user_id'
      and identifier.issuer = v_provider_issuer
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;

    return jsonb_build_object(
      'state', 'awaiting_external_access',
      'offering_key', p_offering_key,
      'request_id', v_request.id
    );
  end if;

  return jsonb_build_object(
    'state', 'pending',
    'offering_key', p_offering_key,
    'request_id', v_request.id
  );
end
$function$;

alter function "public"."request_course_access"(text, text) owner to "ainigma_function_owner";

create or replace function public.request_my_course_repository (
  p_offering_key text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_access_request_id uuid;
  v_external_group_id text;
  v_external_group_handle text;
begin
  select
    course.id,
    access_row.access_request_id,
    access_row.external_group_id,
    access_row.external_group_handle
  into
    v_course_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.external_course_access as access_row
    on access_row.course_id = course.id
   and access_row.profile_id = v_profile_id
   and access_row.state = 'active'
   and access_row.external_user_handle is not null
  join private.course_access_requests as request_row
    on request_row.id = access_row.access_request_id
   and request_row.course_id = access_row.course_id
   and request_row.requester_profile_id = access_row.profile_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
   and organization.external_group_id = access_row.external_group_id
   and organization.external_group_handle = access_row.external_group_handle
  where course.offering_key = p_offering_key
    and course.status = 'published'
  for update of access_row;

  if v_course_id is null then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  insert into private.course_repository_provisioning (
    course_id,
    profile_id,
    access_request_id,
    external_group_id,
    external_group_handle
  ) values (
    v_course_id,
    v_profile_id,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

alter function "public"."request_my_course_repository"(text) owner to "ainigma_function_owner";

create or replace function public.update_my_profile (
  p_display_name text
)
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language sql
  security definer
  set search_path to ''
BEGIN ATOMIC
 update public.profiles profile
  set display_name = update_my_profile.p_display_name
   where (profile.id = private.current_profile_id())
   RETURNING profile.display_name,
     profile.created_at,
     profile.updated_at;
end;

alter function "public"."update_my_profile"(text) owner to "ainigma_function_owner";

alter table "private"."auth_user_links"
  add constraint "auth_user_links_auth_user_id_fkey" foreign key (auth_user_id) references auth.users(id) on delete cascade;

alter table "private"."course_access_requests"
  add constraint "course_access_requests_decision_shape_check"
    check
    ((((status = ANY (ARRAY['pending'::private.course_access_request_status, 'cancelled'::private.course_access_request_status])) AND (decided_at IS NULL) AND (decided_by IS NULL))
    OR ((status = 'approved'::private.course_access_request_status) AND (decided_at IS NOT NULL) AND ((decided_by IS
    NOT NULL) OR (decision_source = 'allowlist'::text))) OR ((status = 'rejected'::private.course_access_request_status) AND (decided_at IS NOT NULL) AND (decided_by IS
    NOT NULL) AND (decision_source = 'owner'::text))));

alter table "private"."course_definition_external_email_domains"
  add constraint "course_definition_external_email_dom_course_definition_key_fkey" foreign key (course_definition_key)
    references private.course_definition_external_groups(course_definition_key) on delete cascade;

alter table "private"."course_definition_releases"
  add constraint "course_definition_releases_external_group_fkey" foreign key (course_definition_key) references private.course_definition_external_groups(course_definition_key)
    on delete restrict;

alter table "private"."course_membership_events"
  add constraint "course_membership_events_shape_check"
    check ((((event_kind = 'created'::text) AND (previous_role IS NULL) AND (previous_status IS NULL)) OR ((event_kind = 'transitioned'::text) AND (previous_role IS
    NOT NULL) AND (previous_status IS NOT NULL))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_request_fkey" foreign key (access_request_id, course_id, profile_id)
    references private.course_access_requests(id, course_id, requester_profile_id) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_group_shape_check"
    check
    ((((state = 'not_started'::private.external_course_access_state) AND (external_group_id IS NULL) AND (external_group_handle IS NULL)) OR ((state <>
    'not_started'::private.external_course_access_state) AND (external_group_id IS NOT NULL) AND (external_group_handle IS NOT NULL))));

alter table "private"."course_repository_provisioning"
  add constraint "course_repository_provisioning_access_identity_fkey" foreign key (course_id, profile_id, access_request_id, external_group_id, external_group_handle)
    references private.external_course_access(course_id, profile_id, access_request_id, external_group_id, external_group_handle) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_request_course_profile_fk" foreign key (access_request_id, course_id, profile_id)
    references private.course_access_requests(id, course_id, requester_profile_id) on delete restrict;

alter table "private"."profile_identifiers"
  add constraint "profile_identifiers_source_auth_user_id_fkey" foreign key (source_auth_user_id) references auth.users(id) on delete set null;

alter table "public"."course_memberships"
  add constraint "course_memberships_access_request_fk" foreign key (created_from_access_request_id) references private.course_access_requests(id) on delete restrict;

alter table "public"."course_memberships"
  add constraint "course_memberships_owner_status_check" check (((role <> 'owner'::private.course_membership_role) OR (status = 'active'::private.course_membership_status)));

alter table "public"."course_memberships"
  add constraint "course_memberships_status_timestamps_check"
    check
    ((((status = 'active'::private.course_membership_status) AND (suspended_at IS NULL) AND (revoked_at IS NULL)) OR ((status = 'suspended'::private.course_membership_status) AND
    (suspended_at IS NOT NULL) AND (revoked_at IS NULL)) OR ((status = 'revoked'::private.course_membership_status) AND (revoked_at IS NOT NULL))));

alter table "public"."courses"
  add constraint "courses_course_definition_external_group_fkey" foreign key (course_definition_key) references private.course_definition_external_groups(course_definition_key)
    on delete restrict;

alter table "public"."courses"
  add constraint "courses_course_definition_release_fkey" foreign key (course_definition_release_id, course_definition_key)
    references private.course_definition_releases(id, course_definition_key) on delete restrict;

alter table "private"."course_access_requests"
  add constraint "course_access_requests_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."course_membership_events"
  add constraint "course_membership_events_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."course_roster_allowlist"
  add constraint "course_roster_allowlist_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "public"."course_memberships"
  add constraint "course_memberships_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."auth_user_links"
  add constraint "auth_user_links_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

alter table "private"."course_access_requests"
  add constraint "course_access_requests_decided_by_fkey" foreign key (decided_by) references public.profiles(id) on delete restrict;

alter table "private"."course_access_requests"
  add constraint "course_access_requests_requester_profile_id_fkey" foreign key (requester_profile_id) references public.profiles(id) on delete restrict;

alter table "private"."course_membership_events"
  add constraint "course_membership_events_actor_profile_id_fkey" foreign key (actor_profile_id) references public.profiles(id) on delete restrict;

alter table "private"."course_membership_events"
  add constraint "course_membership_events_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

alter table "private"."course_roster_allowlist"
  add constraint "course_roster_allowlist_imported_by_fkey" foreign key (imported_by) references public.profiles(id) on delete restrict;

alter table "private"."external_course_access"
  add constraint "external_course_access_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

alter table "private"."profile_identifiers"
  add constraint "profile_identifiers_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

alter table "public"."course_memberships"
  add constraint "course_memberships_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

create view "private"."auth_identities" AS  SELECT id,
    user_id,
    provider_id,
    provider,
    identity_data,
    created_at,
    updated_at
   FROM auth.identities identity_row;

create or replace function private.report_identity_anomalies()
  returns table (
    anomaly          text,
    profile_id       uuid,
    auth_user_id     uuid,
    auth_identity_id uuid,
    detail           text
  )
  language sql
  stable
  security definer
  set search_path to ''
BEGIN ATOMIC
 select 'orphan_profile'::text
  AS text,
     profile.id,
     NULL::uuid AS uuid,
     NULL::uuid AS uuid,
     'profile has no Auth user link'::text AS text
    FROM public.profiles profile
   WHERE (NOT (EXISTS ( SELECT 1
            FROM private.auth_user_links link
           WHERE (link.profile_id = profile.id))))
 UNION ALL
  SELECT 'unlinked_auth_identity'::text AS text,
     NULL::uuid AS uuid,
     identity_row.user_id,
     identity_row.id,
     'Auth identity user has no application profile link'::text AS text
    FROM private.auth_identities identity_row
   WHERE (NOT (EXISTS ( SELECT 1
            FROM private.auth_user_links link
           WHERE (link.auth_user_id = identity_row.user_id))));
END;

alter function "private"."report_identity_anomalies"() owner to "ainigma_function_owner";

create view "private"."auth_users" AS  SELECT id,
    created_at,
    deleted_at
   FROM auth.users auth_user;

create index auth_user_links_profile_id_idx on private.auth_user_links using btree (profile_id);

create index course_access_requests_course_status_idx on private.course_access_requests using btree (course_id, status, requested_at);

create unique index course_access_requests_pending_uidx on private.course_access_requests using btree (course_id, requester_profile_id)
  where (status = 'pending'::private.course_access_request_status);

create index course_definition_external_groups_group_id_idx on private.course_definition_external_groups using btree (external_group_id);

create index course_definition_releases_latest_idx on private.course_definition_releases using btree (course_definition_key, created_at desc, id);

create index course_membership_events_course_created_idx on private.course_membership_events using btree (course_id, created_at desc);

create index course_membership_events_profile_created_idx on private.course_membership_events using btree (profile_id, created_at desc);

create index course_repository_provisioning_claim_idx on private.course_repository_provisioning using btree (state, next_attempt_at, lease_expires_at, updated_at);

create unique index course_repository_provisioning_org_name_uidx on private.course_repository_provisioning using btree (external_group_id, repository_name)
  where (repository_name is not null);

create unique index course_repository_provisioning_repository_id_uidx on private.course_repository_provisioning using btree (external_repository_id)
  where (external_repository_id is not null);

create unique index course_roster_allowlist_active_uidx on private.course_roster_allowlist
  using btree (course_id, identifier_kind, identifier_issuer, identifier_scheme_version, normalized_identifier_value)
  where (status = 'active'::text);

create index course_roster_allowlist_course_idx on private.course_roster_allowlist using btree (course_id, status);

create unique index external_course_access_request_uidx on private.external_course_access using btree (access_request_id);

create unique index profile_identifiers_active_external_user_uidx on private.profile_identifiers using btree (profile_id, issuer, scheme_version)
  where ((kind = 'external_user_id'::text) AND (revoked_at is null));

create unique index profile_identifiers_active_identity_uidx on private.profile_identifiers using btree (kind, issuer, scheme_version, normalized_value)
  where (revoked_at is null);

create index profile_identifiers_profile_active_idx on private.profile_identifiers using btree (profile_id, kind, issuer, scheme_version)
  where (revoked_at is null);

create index profile_identifiers_source_auth_user_idx on private.profile_identifiers using btree (source_auth_user_id)
  where (source_auth_user_id is not null);

create unique index course_memberships_access_request_uidx on public.course_memberships using btree (created_from_access_request_id)
  where (created_from_access_request_id is not null);

create index course_memberships_course_role_status_idx on public.course_memberships using btree (course_id, role, status);

create unique index course_memberships_one_active_owner_uidx on public.course_memberships using btree (course_id)
  where ((role = 'owner'::private.course_membership_role) AND (status = 'active'::private.course_membership_status));

create index course_memberships_profile_status_role_idx on public.course_memberships using btree (profile_id, status, role, course_id);

create index courses_course_definition_key_idx on public.courses using btree (course_definition_key);

create index courses_course_definition_release_id_idx on public.courses using btree (course_definition_release_id);

create index courses_status_window_idx on public.courses using btree (status, starts_at, ends_at);

create trigger on_auth_identity_changed
  after insert or update of provider_id, identity_data, provider on auth.identities
  for each row
  execute function private.handle_auth_identity_changed();

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function private.handle_auth_user_created();

create trigger course_definition_releases_reject_mutation
  before delete or update on private.course_definition_releases
  for each row
  execute function private.reject_mutation();

create trigger course_membership_events_reject_mutation
  before delete or update on private.course_membership_events
  for each row
  execute function private.reject_mutation();

create trigger course_repository_provisioning_set_updated_at
  before update on private.course_repository_provisioning
  for each row
  execute function private.set_updated_at();

create trigger profile_identifiers_set_updated_at
  before update on private.profile_identifiers
  for each row
  execute function private.set_updated_at();

create trigger courses_set_updated_at
  before update on public.courses
  for each row
  execute function private.set_updated_at();

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function private.set_updated_at();

create policy "course_access_requests_function_access" on "private"."course_access_requests"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

create policy "course_repository_provisioning_function_access" on "private"."course_repository_provisioning"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

create policy "course_roster_allowlist_function_access" on "private"."course_roster_allowlist"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

create policy "external_course_access_function_access" on "private"."external_course_access"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

create policy "course_memberships_function_owner_access" on "public"."course_memberships"
  for all
  to "ainigma_function_owner"
  using (true)
  with check (true);

create policy "course_memberships_select_authorized" on "public"."course_memberships"
  for select
  to "authenticated"
  using
    (((profile_id = ( select private.current_profile_id() as current_profile_id)) or ( select private.has_course_role(course_memberships.course_id,
    ARRAY['owner'::private.course_membership_role, 'instructor'::private.course_membership_role]) as has_course_role)));

create policy "courses_function_owner_access" on "public"."courses"
  for all
  to "ainigma_function_owner"
  using (true)
  with check (true);

create policy "courses_select_enrolled" on "public"."courses"
  for select
  to "authenticated"
  using
    ((((status = 'published'::private.course_offering_status) AND ( select private.has_course_role(courses.id, ARRAY['owner'::private.course_membership_role,
    'instructor'::private.course_membership_role,
    'learner'::private.course_membership_role]) as has_course_role)) or
    ((status = 'draft'::private.course_offering_status) AND ( select private.has_course_role(courses.id, ARRAY['owner'::private.course_membership_role,
    'instructor'::private.course_membership_role]) as has_course_role))));

create policy "profiles_function_owner_access" on "public"."profiles"
  for all
  to "ainigma_function_owner"
  using (true)
  with check (true);

create policy "profiles_select_authorized" on "public"."profiles"
  for select
  to "authenticated"
  using (( select private.can_view_profile(profiles.id) as can_view_profile));

create policy "profiles_update_own_display_name" on "public"."profiles"
  for update
  to "authenticated"
  using ((id = ( select private.current_profile_id() as current_profile_id)))
  with check ((id = ( SELECT private.current_profile_id() AS current_profile_id)));

comment on column "private"."course_definition_external_groups"."email_domain_enforced" is 'Whether email invitation targets must match the configured domain suffixes.';

comment on column "private"."course_definition_external_groups"."external_group_handle" is 'Current provider group handle for diagnostics and display; external_group_id is authoritative.';

comment on column "private"."course_definition_external_groups"."external_group_id" is 'Stable provider group ID used for authorization; the handle is only a display snapshot.';

comment on column "private"."course_definition_external_groups"."provider_issuer" is 'Identifier issuer used to select verified profile facts for this provider instance.';

comment on column "private"."course_definition_external_groups"."provider_kind" is 'Provider adapter key, currently github; it selects the external platform implementation.';

comment on column "private"."course_definition_releases"."artifact_ref" is 'Immutable deployable artifact reference resolved by the compiler and deployment system.';

comment on column "private"."course_repository_provisioning"."external_repository_id" is 'Stable provider repository ID; used instead of the mutable repository name for reconciliation.';

comment on column "private"."course_repository_provisioning"."repository_name" is 'Deterministic offering-specific repository name, normally submissions-<offering_key>-<user_handle>.';

comment on column "private"."external_course_access"."external_invitation_id" is 'Provider invitation ID for the current invitation attempt; acceptance must match this ID.';

comment on column "private"."external_course_access"."external_user_handle" is 'Current provider login or handle cached from verified membership; it may change and is not an identity key.';

comment on column "private"."external_course_access"."external_user_id" is 'Stable external provider account ID. This is the identity key for the offering access record.';

comment on column "public"."courses"."course_definition_key" is 'Immutable key of the reusable Git-authored course definition rendered for this offering.';

comment on column "public"."courses"."course_definition_release_id" is 'Exact compiler release currently rendered for this offering; ended offerings stop advancing.';

comment on column "public"."courses"."offering_key" is 'Globally unique immutable key for one term, cohort, or operational course space.';

comment on table "private"."course_definition_external_email_domains" is 'Allowed email domain suffixes for invitations to a course definition.';

comment on table "private"."course_definition_external_groups" is 'The trusted external provider group configured for each reusable course definition.';

comment on table "private"."course_definition_releases" is 'Immutable Ainigma compiler outputs for reusable course definitions.';

comment on table "private"."course_repository_provisioning" is 'Durable idempotent outbox for one external submissions repository per offering and profile.';

comment on table "public"."courses" is 'Operational course offerings. Titles, navigation, and authored content remain in Git.';

comment on table "public"."profiles" is 'Provider-neutral application identities. Authorization claims remain private.';

revoke all on function "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) from public;

grant execute on function "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."advance_open_course_offerings_to_release"(uuid) from public;

grant execute on function "private"."advance_open_course_offerings_to_release"(uuid) to "ainigma_maintenance";

revoke all on function "private"."branch_course_offering"(text, uuid, text, uuid, timestamp with time zone, timestamp with time zone, text) from public;

grant execute on function "private"."branch_course_offering"(text, uuid, text, uuid, timestamp with time zone, timestamp with time zone, text) to "ainigma_maintenance";

revoke all on function "private"."can_view_profile"(uuid) from public;

grant execute on function "private"."can_view_profile"(uuid) to "authenticated";

revoke all on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) from public;

grant execute on function "private"."claim_course_repository_provisioning"(integer, uuid, uuid) to "ainigma_maintenance";

revoke all on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) from public;

grant execute on function "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) from public;

grant execute on function "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."current_profile_id"() from public;

grant execute on function "private"."current_profile_id"() to "authenticated";

revoke all on function "private"."ensure_auth_user_profile"(uuid) from public;

grant execute on function "private"."ensure_auth_user_profile"(uuid) to "ainigma_maintenance";

revoke all on function "private"."handle_auth_identity_changed"() from public;

revoke all on function "private"."handle_auth_user_created"() from public;

revoke all on function "private"."has_course_role"(uuid, private.course_membership_role[]) from public;

grant execute on function "private"."has_course_role"(uuid, private.course_membership_role[]) to "authenticated";

revoke all on function "private"."list_external_course_access_to_reconcile"() from public;

grant execute on function "private"."list_external_course_access_to_reconcile"() to "ainigma_maintenance";

revoke all on function "private"."reconcile_auth_identities"() from public;

grant execute on function "private"."reconcile_auth_identities"() to "ainigma_maintenance";

revoke all on function "private"."reconcile_auth_users"() from public;

grant execute on function "private"."reconcile_auth_users"() to "ainigma_maintenance";

revoke all on function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) from public;

grant execute on function "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_check_failure"(uuid, uuid, text) from public;

grant execute on function "private"."record_external_course_access_check_failure"(uuid, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) from public;

grant execute on function "private"."record_external_course_access_invitation"(uuid, uuid, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_membership_absence"(uuid, uuid) from public;

grant execute on function "private"."record_external_course_access_membership_absence"(uuid, uuid) to "ainigma_maintenance";

revoke all on function "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text) from public;

grant execute on function "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text) to "ainigma_maintenance";

revoke all on function "private"."register_course_definition_release"(text, text, text, text) from public;

grant execute on function "private"."register_course_definition_release"(text, text, text, text) to "ainigma_maintenance";

revoke all on function "private"."reject_mutation"() from public;

grant execute on function "private"."reject_mutation"() to "postgres";

revoke all on function "private"."report_identity_anomalies"() from public;

grant execute on function "private"."report_identity_anomalies"() to "ainigma_maintenance";

revoke all on function "private"."request_auth_user_id"() from public;

grant execute on function "private"."request_auth_user_id"() to "ainigma_function_owner", "postgres";

revoke all on function "private"."set_updated_at"() from public;

grant execute on function "private"."set_updated_at"() to "postgres";

revoke all on function "private"."sync_auth_identity"(uuid) from public;

grant execute on function "private"."sync_auth_identity"(uuid) to "ainigma_maintenance";

revoke all on function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) from public;

grant execute on function "private"."transfer_course_ownership"(uuid, uuid, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) from public;

grant execute
  on function "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text)
  to "ainigma_maintenance";

revoke all on function "private"."upsert_verified_identifier"(uuid, text, text, integer, text, timestamp with time zone, uuid, text) from public;

revoke all on function "public"."approve_course_access_requests"(text, uuid[]) from public;

revoke all on function "public"."approve_course_access_requests"(text, uuid[]) from "ainigma_function_owner";

grant execute on function "public"."approve_course_access_requests"(text, uuid[]) to "ainigma_function_owner";

grant execute on function "public"."approve_course_access_requests"(text, uuid[]) to "authenticated";

revoke all on function "public"."get_my_course_repository"(text) from public;

revoke all on function "public"."get_my_course_repository"(text) from "ainigma_function_owner";

grant execute on function "public"."get_my_course_repository"(text) to "ainigma_function_owner";

grant execute on function "public"."get_my_course_repository"(text) to "authenticated";

revoke all on function "public"."get_my_profile"() from public;

revoke all on function "public"."get_my_profile"() from "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "authenticated";

revoke all on function "public"."list_available_courses"() from public;

revoke all on function "public"."list_available_courses"() from "ainigma_function_owner";

grant execute on function "public"."list_available_courses"() to "ainigma_function_owner";

grant execute on function "public"."list_available_courses"() to "anon", "authenticated";

revoke all on function "public"."list_course_access_requests"(text, private.course_access_request_status, text) from public;

revoke all on function "public"."list_course_access_requests"(text, private.course_access_request_status, text) from "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, private.course_access_request_status, text) to "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, private.course_access_request_status, text) to "authenticated";

revoke all on function "public"."list_course_roster"(text) from public;

revoke all on function "public"."list_course_roster"(text) from "ainigma_function_owner";

grant execute on function "public"."list_course_roster"(text) to "ainigma_function_owner";

grant execute on function "public"."list_course_roster"(text) to "authenticated";

revoke all on function "public"."list_my_course_access_requests"() from public;

revoke all on function "public"."list_my_course_access_requests"() from "ainigma_function_owner";

grant execute on function "public"."list_my_course_access_requests"() to "ainigma_function_owner";

grant execute on function "public"."list_my_course_access_requests"() to "authenticated";

revoke all on function "public"."list_my_courses"() from public;

revoke all on function "public"."list_my_courses"() from "ainigma_function_owner";

grant execute on function "public"."list_my_courses"() to "ainigma_function_owner";

grant execute on function "public"."list_my_courses"() to "authenticated";

revoke all on function "public"."reject_course_access_requests"(text, uuid[], text) from public;

revoke all on function "public"."reject_course_access_requests"(text, uuid[], text) from "ainigma_function_owner";

grant execute on function "public"."reject_course_access_requests"(text, uuid[], text) to "ainigma_function_owner";

grant execute on function "public"."reject_course_access_requests"(text, uuid[], text) to "authenticated";

revoke all on function "public"."request_course_access"(text, text) from public;

revoke all on function "public"."request_course_access"(text, text) from "ainigma_function_owner";

grant execute on function "public"."request_course_access"(text, text) to "ainigma_function_owner";

grant execute on function "public"."request_course_access"(text, text) to "authenticated";

revoke all on function "public"."request_my_course_repository"(text) from public;

revoke all on function "public"."request_my_course_repository"(text) from "ainigma_function_owner";

grant execute on function "public"."request_my_course_repository"(text) to "ainigma_function_owner";

grant execute on function "public"."request_my_course_repository"(text) to "authenticated";

revoke all on function "public"."update_my_profile"(text) from public;

revoke all on function "public"."update_my_profile"(text) from "ainigma_function_owner";

grant execute on function "public"."update_my_profile"(text) to "ainigma_function_owner";

grant execute on function "public"."update_my_profile"(text) to "authenticated";

revoke all on schema "private" from "ainigma_maintenance";

grant usage on schema "private" to "ainigma_maintenance";

grant insert, select on table "private"."auth_user_links" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."auth_user_links" to "postgres";

grant insert, select, update on table "private"."course_access_requests" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_access_requests" to "postgres";

grant select on table "private"."course_definition_external_email_domains" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_external_email_domains" to "postgres";

grant select on table "private"."course_definition_external_groups" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_external_groups" to "postgres";

grant insert, select on table "private"."course_definition_releases" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_releases" to "postgres";

grant insert, select on table "private"."course_membership_events" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_membership_events" to "postgres";

grant insert, select, update on table "private"."course_repository_provisioning" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_repository_provisioning" to "postgres";

grant insert, select, update on table "private"."course_roster_allowlist" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_roster_allowlist" to "postgres";

grant insert, select, update on table "private"."external_course_access" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."external_course_access" to "postgres";

grant insert, select, update on table "private"."profile_identifiers" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."profile_identifiers" to "postgres";

grant insert, select, update on table "public"."course_memberships" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."course_memberships" to "postgres";

grant insert, select, update on table "public"."courses" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."courses" to "postgres";

grant insert, select, update on table "public"."profiles" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."profiles" to "postgres";

grant usage on type "private"."course_access_request_status" to "postgres";

grant usage on type "private"."course_enrollment_mode" to "postgres";

grant usage on type "private"."course_membership_role" to "postgres";

grant usage on type "private"."course_membership_status" to "postgres";

grant usage on type "private"."course_offering_status" to "postgres";

grant usage on type "private"."external_course_access_state" to "postgres";

grant select on table "private"."auth_identities" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."auth_identities" to "postgres";

grant select on table "private"."auth_users" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."auth_users" to "postgres";
