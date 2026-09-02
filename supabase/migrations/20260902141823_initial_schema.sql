SET local check_function_bodies = off;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "service_role";

CREATE TABLE "private"."auth_user_links" (
  "auth_user_id" uuid                     NOT NULL,
  "profile_id"   uuid                     NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "auth_user_links_pkey" PRIMARY KEY (auth_user_id)
);

CREATE TABLE "private"."course_access_requests" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "course_id"            uuid                     NOT NULL,
  "requester_profile_id" uuid                     NOT NULL,
  "reason"               text,
  "decision_source"      text                     NOT NULL DEFAULT 'owner'::text,
  "requested_at"         timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "decided_at"           timestamp with time zone,
  "decided_by"           uuid,
  "decision_reason"      text,
  CONSTRAINT "course_access_requests_decision_source_check" CHECK ((decision_source = ANY (ARRAY['owner'::text, 'allowlist'::text]))),
  CONSTRAINT "course_access_requests_id_course_profile_unique" UNIQUE (id, course_id, requester_profile_id),
  CONSTRAINT "course_access_requests_pkey" PRIMARY KEY (id),
  CONSTRAINT "course_access_requests_reason_check" CHECK (((reason IS NULL) OR ((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000)))))
);

ALTER TABLE "private"."course_access_requests"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."course_access_requests"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "private"."course_definition_external_email_domains" (
  "course_definition_key" text NOT NULL,
  "domain_suffix"         text NOT NULL,
  CONSTRAINT "course_definition_external_email_domains_pkey" PRIMARY KEY (course_definition_key, domain_suffix),
  CONSTRAINT "course_definition_external_email_domains_suffix_check"
    CHECK
    (((domain_suffix = lower(btrim(domain_suffix))) AND (domain_suffix !~ '[[:space:]@]'::text) AND (domain_suffix !~ '(^[.]|[.]$|[.][.])'::text) AND (domain_suffix ~
    '^[a-z0-9-]+([.][a-z0-9-]+)*$'::text)))
);

CREATE TABLE "private"."course_definition_external_groups" (
  "course_definition_key" text                     NOT NULL,
  "provider_kind"         text                     NOT NULL,
  "provider_issuer"       text                     NOT NULL,
  "external_group_id"     text                     NOT NULL,
  "external_group_handle" text                     NOT NULL,
  "email_domain_enforced" boolean                  NOT NULL DEFAULT true,
  "created_at"            timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "course_definition_external_groups_definition_key_check" CHECK ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  CONSTRAINT "course_definition_external_groups_group_id_check"
    CHECK (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255)))),
  CONSTRAINT "course_definition_external_groups_org_slug_check"
    CHECK (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255)))),
  CONSTRAINT "course_definition_external_groups_pkey" PRIMARY KEY (course_definition_key),
  CONSTRAINT "course_definition_external_groups_provider_issuer_check"
    CHECK
    (((provider_issuer = btrim(provider_issuer)) AND ((char_length(provider_issuer) >= 1) AND (char_length(provider_issuer) <= 255)) AND (provider_issuer !~ '[[:space:]]'::text))),
  CONSTRAINT "course_definition_external_groups_provider_kind_check" CHECK (((provider_kind = btrim(provider_kind)) AND (provider_kind ~ '^[a-z][a-z0-9_]{0,63}$'::text))),
  CONSTRAINT "course_definition_external_groups_repository_target_unique" UNIQUE (course_definition_key, external_group_id, external_group_handle)
);

CREATE TABLE "private"."course_definition_releases" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "course_definition_key" text                     NOT NULL,
  "source_commit_sha"     text                     NOT NULL,
  "course_release_digest" text                     NOT NULL,
  "artifact_ref"          text                     NOT NULL,
  "created_at"            timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "course_definition_releases_artifact_ref_check"
    CHECK (((artifact_ref = btrim(artifact_ref)) AND ((char_length(artifact_ref) >= 1) AND (char_length(artifact_ref) <= 2048)))),
  CONSTRAINT "course_definition_releases_definition_digest_unique" UNIQUE (course_definition_key, course_release_digest),
  CONSTRAINT "course_definition_releases_definition_key_check" CHECK ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  CONSTRAINT "course_definition_releases_digest_check" CHECK ((course_release_digest ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "course_definition_releases_id_definition_key_unique" UNIQUE (id, course_definition_key),
  CONSTRAINT "course_definition_releases_pkey" PRIMARY KEY (id),
  CONSTRAINT "course_definition_releases_source_commit_sha_check" CHECK ((source_commit_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'::text))
);

CREATE TABLE "private"."course_membership_events" (
  "id"               bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "course_id"        uuid                     NOT NULL,
  "profile_id"       uuid                     NOT NULL,
  "event_kind"       text                     NOT NULL,
  "actor_profile_id" uuid,
  "reason"           text                     NOT NULL,
  "created_at"       timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "course_membership_events_kind_check" CHECK ((event_kind = ANY (ARRAY['created'::text, 'transitioned'::text]))),
  CONSTRAINT "course_membership_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "course_membership_events_reason_check" CHECK (((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000))))
);

CREATE TABLE "private"."course_repository_provisioning" (
  "course_id"               uuid                     NOT NULL,
  "profile_id"              uuid                     NOT NULL,
  "course_definition_key"   text                     NOT NULL,
  "access_request_id"       uuid                     NOT NULL,
  "external_group_id"       text                     NOT NULL,
  "external_group_handle"   text                     NOT NULL,
  "repository_name"         text,
  "external_repository_id"  text,
  "external_repository_url" text,
  "state"                   text                     NOT NULL DEFAULT 'queued'::text,
  "attempt_count"           integer                  NOT NULL DEFAULT 0,
  "lease_token"             uuid,
  "lease_expires_at"        timestamp with time zone,
  "next_attempt_at"         timestamp with time zone DEFAULT clock_timestamp(),
  "last_error"              text,
  "created_at"              timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "updated_at"              timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "course_repository_provisioning_attempt_check" CHECK ((attempt_count >= 0)),
  CONSTRAINT "course_repository_provisioning_error_check" CHECK ((((state = ANY (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS
    NOT NULL) AND (last_error = btrim(last_error)) AND ((char_length(last_error) >= 1) AND (char_length(last_error) <= 1000))) OR
    ((state <> ALL (ARRAY['retry_wait'::text, 'blocked'::text])) AND (last_error IS NULL)))),
  CONSTRAINT "course_repository_provisioning_group_handle_check"
    CHECK (((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND (char_length(external_group_handle) <= 255)))),
  CONSTRAINT "course_repository_provisioning_group_id_check"
    CHECK (((external_group_id = btrim(external_group_id)) AND ((char_length(external_group_id) >= 1) AND (char_length(external_group_id) <= 255)))),
  CONSTRAINT "course_repository_provisioning_lease_check" CHECK ((((state = 'provisioning'::text) AND (lease_token IS NOT NULL) AND (lease_expires_at IS
    NOT NULL)) OR ((state <> 'provisioning'::text) AND (lease_token IS NULL) AND (lease_expires_at IS NULL)))),
  CONSTRAINT "course_repository_provisioning_name_check"
    CHECK (((repository_name IS NULL) OR ((repository_name = btrim(repository_name)) AND ((char_length(repository_name) >= 1) AND (char_length(repository_name) <= 100))))),
  CONSTRAINT "course_repository_provisioning_next_attempt_check" CHECK ((((state = ANY (ARRAY['queued'::text, 'retry_wait'::text, 'provisioning'::text])) AND (next_attempt_at IS
    NOT NULL)) OR ((state = ANY (ARRAY['ready'::text, 'blocked'::text])) AND (next_attempt_at IS NULL)))),
  CONSTRAINT "course_repository_provisioning_pkey" PRIMARY KEY (course_id, profile_id),
  CONSTRAINT "course_repository_provisioning_ready_shape_check" CHECK ((((state = 'ready'::text) AND (repository_name IS NOT NULL) AND (external_repository_id IS
    NOT NULL) AND (external_repository_url IS NOT NULL)) OR (state <> 'ready'::text))),
  CONSTRAINT "course_repository_provisioning_repository_id_check"
    CHECK
    (((external_repository_id IS NULL) OR ((external_repository_id = btrim(external_repository_id)) AND ((char_length(external_repository_id) >= 1) AND
    (char_length(external_repository_id) <= 255))))),
  CONSTRAINT "course_repository_provisioning_state_check" CHECK ((state = ANY (ARRAY['queued'::text, 'provisioning'::text, 'retry_wait'::text, 'ready'::text, 'blocked'::text]))),
  CONSTRAINT "course_repository_provisioning_url_check"
    CHECK
    (((external_repository_url IS NULL) OR ((external_repository_url = btrim(external_repository_url)) AND ((char_length(external_repository_url) >= 1) AND
    (char_length(external_repository_url) <= 2048)))))
);

ALTER TABLE "private"."course_repository_provisioning"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."course_repository_provisioning"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "private"."course_roster_allowlist" (
  "id"                          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "course_id"                   uuid                     NOT NULL,
  "identifier_kind"             text                     NOT NULL,
  "identifier_issuer"           text                     NOT NULL,
  "identifier_scheme_version"   integer                  NOT NULL,
  "normalized_identifier_value" text                     NOT NULL,
  "source"                      text                     NOT NULL,
  "status"                      text                     NOT NULL DEFAULT 'active'::text,
  "imported_at"                 timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "imported_by"                 uuid,
  "revoked_at"                  timestamp with time zone,
  CONSTRAINT "course_roster_allowlist_issuer_check"
    CHECK (((identifier_issuer = btrim(identifier_issuer)) AND ((char_length(identifier_issuer) >= 1) AND (char_length(identifier_issuer) <= 255)))),
  CONSTRAINT "course_roster_allowlist_kind_check" CHECK ((identifier_kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'student_identifier'::text]))),
  CONSTRAINT "course_roster_allowlist_pkey" PRIMARY KEY (id),
  CONSTRAINT "course_roster_allowlist_revoked_shape_check" CHECK ((((status = 'active'::text) AND (revoked_at IS NULL)) OR ((status = 'revoked'::text) AND (revoked_at IS
    NOT NULL)))),
  CONSTRAINT "course_roster_allowlist_scheme_check" CHECK ((identifier_scheme_version > 0)),
  CONSTRAINT "course_roster_allowlist_source_check" CHECK (((source = btrim(source)) AND ((char_length(source) >= 1) AND (char_length(source) <= 255)))),
  CONSTRAINT "course_roster_allowlist_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text]))),
  CONSTRAINT "course_roster_allowlist_value_check"
    CHECK
    (((normalized_identifier_value = btrim(normalized_identifier_value)) AND ((char_length(normalized_identifier_value) >= 1) AND (char_length(normalized_identifier_value) <=
    512))))
);

ALTER TABLE "private"."course_roster_allowlist"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."course_roster_allowlist"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "private"."external_course_access" (
  "course_id"                       uuid                     NOT NULL,
  "profile_id"                      uuid                     NOT NULL,
  "access_request_id"               uuid                     NOT NULL,
  "external_group_id"               text,
  "external_group_handle"           text,
  "external_user_id"                text                     NOT NULL,
  "external_user_handle"            text,
  "external_invitation_id"          text,
  "invitation_target"               text,
  "invited_at"                      timestamp with time zone,
  "accepted_at"                     timestamp with time zone,
  "last_checked_at"                 timestamp with time zone,
  "failure_code"                    text,
  "consecutive_membership_absences" integer                  NOT NULL DEFAULT 0,
  CONSTRAINT "external_course_access_failure_check"
    CHECK (((failure_code IS NULL) OR ((failure_code = btrim(failure_code)) AND ((char_length(failure_code) >= 1) AND (char_length(failure_code) <= 255))))),
  CONSTRAINT "external_course_access_group_handle_check"
    CHECK
    (((external_group_handle IS NULL) OR ((external_group_handle = btrim(external_group_handle)) AND ((char_length(external_group_handle) >= 1) AND
    (char_length(external_group_handle) <= 255))))),
  CONSTRAINT "external_course_access_invitation_id_check"
    CHECK
    (((external_invitation_id IS NULL) OR ((external_invitation_id = btrim(external_invitation_id)) AND ((char_length(external_invitation_id) >= 1) AND
    (char_length(external_invitation_id) <= 255))))),
  CONSTRAINT "external_course_access_invitation_target_check"
    CHECK
    (((invitation_target IS NULL) OR ((invitation_target = btrim(invitation_target)) AND ((char_length(invitation_target) >= 1) AND (char_length(invitation_target) <= 512))))),
  CONSTRAINT "external_course_access_membership_absences_check" CHECK ((consecutive_membership_absences >= 0)),
  CONSTRAINT "external_course_access_pkey" PRIMARY KEY (course_id, profile_id),
  CONSTRAINT "external_course_access_repository_identity_unique" UNIQUE (course_id, profile_id, access_request_id, external_group_id, external_group_handle),
  CONSTRAINT "external_course_access_user_handle_check"
    CHECK
    (((external_user_handle IS NULL) OR ((external_user_handle = btrim(external_user_handle)) AND ((char_length(external_user_handle) >= 1) AND (char_length(external_user_handle)
    <= 255)) AND (external_user_handle !~ '[[:space:]]'::text)))),
  CONSTRAINT "external_course_access_user_id_check"
    CHECK (((external_user_id = btrim(external_user_id)) AND ((char_length(external_user_id) >= 1) AND (char_length(external_user_id) <= 255))))
);

ALTER TABLE "private"."external_course_access"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."external_course_access"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "private"."profile_identifiers" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "profile_id"           uuid                     NOT NULL,
  "kind"                 text                     NOT NULL,
  "issuer"               text                     NOT NULL,
  "scheme_version"       integer                  NOT NULL,
  "normalized_value"     text                     NOT NULL,
  "verified_at"          timestamp with time zone NOT NULL,
  "last_verified_at"     timestamp with time zone NOT NULL,
  "revoked_at"           timestamp with time zone,
  "source_auth_user_id"  uuid,
  "provider_identity_id" text,
  "created_at"           timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "profile_identifiers_issuer_check" CHECK (((issuer = btrim(issuer)) AND ((char_length(issuer) >= 1) AND (char_length(issuer) <= 255)))),
  CONSTRAINT "profile_identifiers_kind_check" CHECK ((kind = ANY (ARRAY['email'::text, 'external_user_id'::text, 'external_user_handle'::text, 'student_identifier'::text]))),
  CONSTRAINT "profile_identifiers_normalized_value_check"
    CHECK (((normalized_value = btrim(normalized_value)) AND ((char_length(normalized_value) >= 1) AND (char_length(normalized_value) <= 512)))),
  CONSTRAINT "profile_identifiers_pkey" PRIMARY KEY (id),
  CONSTRAINT "profile_identifiers_provider_identity_id_check"
    CHECK (((provider_identity_id IS NULL) OR ((char_length(provider_identity_id) >= 1) AND (char_length(provider_identity_id) <= 255)))),
  CONSTRAINT "profile_identifiers_scheme_version_check" CHECK ((scheme_version > 0)),
  CONSTRAINT "profile_identifiers_verification_window_check" CHECK (((last_verified_at >= verified_at) AND ((revoked_at IS NULL) OR (revoked_at >= verified_at))))
);

CREATE TABLE "public"."course_memberships" (
  "course_id"                      uuid                     NOT NULL,
  "profile_id"                     uuid                     NOT NULL,
  "created_at"                     timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "suspended_at"                   timestamp with time zone,
  "revoked_at"                     timestamp with time zone,
  "created_from_access_request_id" uuid,
  CONSTRAINT "course_memberships_pkey" PRIMARY KEY (course_id, profile_id)
);

ALTER TABLE "public"."course_memberships"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."course_memberships"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "public"."courses" (
  "id"                           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "offering_key"                 text                     NOT NULL,
  "course_definition_key"        text                     NOT NULL,
  "course_definition_release_id" uuid                     NOT NULL,
  "code"                         text                     NOT NULL,
  "starts_at"                    timestamp with time zone,
  "ends_at"                      timestamp with time zone,
  "external_url"                 text,
  "created_at"                   timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "updated_at"                   timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "courses_code_check" CHECK (((code = btrim(code)) AND ((char_length(code) >= 1) AND (char_length(code) <= 32)))),
  CONSTRAINT "courses_course_definition_key_check" CHECK ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  CONSTRAINT "courses_external_url_check" CHECK (((external_url IS NULL) OR ((char_length(external_url) <= 2048) AND (external_url ~ '^https?://'::text)))),
  CONSTRAINT "courses_id_definition_key_unique" UNIQUE (id, course_definition_key),
  CONSTRAINT "courses_offering_key_check" CHECK ((offering_key ~ '^[a-z][a-z0-9-]{2,127}$'::text)),
  CONSTRAINT "courses_offering_key_key" UNIQUE (offering_key),
  CONSTRAINT "courses_pkey" PRIMARY KEY (id),
  CONSTRAINT "courses_time_window_check" CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at)))
);

ALTER TABLE "public"."courses"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."courses"
  FORCE ROW LEVEL SECURITY;

CREATE TABLE "public"."profiles" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "display_name" text                     NOT NULL DEFAULT 'Learner'::text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "profiles_display_name_check"
    CHECK (((display_name IS NULL) OR ((display_name = btrim(display_name)) AND ((char_length(display_name) >= 1) AND (char_length(display_name) <= 100))))),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profiles"
  FORCE ROW LEVEL SECURITY;

CREATE TYPE "private"."course_access_request_status" AS ENUM (
  'pending',
  'approved',
  'rejected',
  'cancelled'
);

ALTER TABLE "private"."course_access_requests"
  ADD COLUMN "status" private.course_access_request_status NOT NULL DEFAULT 'pending'::private.course_access_request_status;

CREATE TYPE "private"."course_enrollment_mode" AS ENUM (
  'approval_required',
  'allowlist_auto',
  'closed'
);

ALTER TABLE "public"."courses"
  ADD COLUMN "enrollment_mode" private.course_enrollment_mode NOT NULL DEFAULT 'approval_required'::private.course_enrollment_mode;

CREATE TYPE "private"."course_membership_role" AS ENUM (
  'owner',
  'instructor',
  'learner'
);

ALTER TABLE "private"."course_access_requests"
  ADD COLUMN "requested_role" private.course_membership_role NOT NULL DEFAULT 'learner'::private.course_membership_role;

ALTER TABLE "private"."course_membership_events"
  ADD COLUMN "previous_role" private.course_membership_role;

ALTER TABLE "private"."course_membership_events"
  ADD COLUMN "new_role" private.course_membership_role NOT NULL;

ALTER TABLE "private"."course_roster_allowlist"
  ADD COLUMN "role" private.course_membership_role NOT NULL DEFAULT 'learner'::private.course_membership_role;

ALTER TABLE "public"."course_memberships"
  ADD COLUMN "role" private.course_membership_role NOT NULL;

CREATE TYPE "private"."course_membership_status" AS ENUM (
  'active',
  'suspended',
  'revoked'
);

ALTER TABLE "private"."course_membership_events"
  ADD COLUMN "previous_status" private.course_membership_status;

ALTER TABLE "private"."course_membership_events"
  ADD COLUMN "new_status" private.course_membership_status NOT NULL;

ALTER TABLE "public"."course_memberships"
  ADD COLUMN "status" private.course_membership_status NOT NULL DEFAULT 'active'::private.course_membership_status;

CREATE TYPE "private"."course_membership_verification" AS ENUM (
  'external_membership',
  'approval_only'
);

ALTER TABLE "public"."courses"
  ADD COLUMN "membership_verification" private.course_membership_verification NOT NULL DEFAULT 'external_membership'::private.course_membership_verification;

CREATE TYPE "private"."course_offering_status" AS ENUM (
  'draft',
  'published',
  'archived'
);

ALTER TABLE "public"."courses"
  ADD COLUMN "status" private.course_offering_status NOT NULL DEFAULT 'draft'::private.course_offering_status;

CREATE TYPE "private"."external_course_access_state" AS ENUM (
  'not_started',
  'invitation_pending',
  'sso_required',
  'active',
  'failed',
  'revoked'
);

ALTER TABLE "private"."external_course_access"
  ADD COLUMN "state" private.external_course_access_state NOT NULL DEFAULT 'not_started'::private.external_course_access_state;

CREATE TYPE "private"."external_invitation_method" AS ENUM (
  'email',
  'external_user_id'
);

ALTER TABLE "private"."external_course_access"
  ADD COLUMN "invitation_method" private.external_invitation_method NOT NULL DEFAULT 'external_user_id'::private.external_invitation_method;

CREATE OR REPLACE FUNCTION private.activate_course_membership_from_request (
  p_access_request_id uuid,
  p_reason            text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_request private.course_access_requests%rowtype;
begin
  if p_access_request_id is null then
    raise exception using errcode = '22004', message = 'access_request_id_required';
  end if;

  if p_reason is null or p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000 then
    raise exception using errcode = '22023', message = 'invalid_course_membership_reason';
  end if;

  perform 1
  from public.courses as course
  join private.course_access_requests as request_row
    on request_row.course_id = course.id
  where request_row.id = p_access_request_id
  for update of course;

  select request_row.*
  into v_request
  from private.course_access_requests as request_row
  where request_row.id = p_access_request_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'access_request_not_found';
  end if;

  if v_request.status <> 'approved' then
    raise exception using errcode = '42501', message = 'course_access_not_approved';
  end if;

  if v_request.requested_role <> 'learner' then
    raise exception using errcode = '22023', message = 'requested_role_not_supported';
  end if;

  insert into public.course_memberships (
    course_id, profile_id, role, status, created_from_access_request_id
  ) values (
    v_request.course_id, v_request.requester_profile_id, 'learner', 'active', v_request.id
  )
  on conflict (course_id, profile_id) do nothing;

  if not found then
    return;
  end if;

  insert into private.course_membership_events (
    course_id, profile_id, event_kind, new_role, new_status, actor_profile_id, reason
  ) values (
    v_request.course_id,
    v_request.requester_profile_id,
    'created',
    'learner',
    'active',
    null,
    p_reason
  );
end
$function$;

ALTER FUNCTION "private"."activate_course_membership_from_request"(uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.add_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_role             private.course_membership_role,
  p_actor_profile_id uuid,
  p_reason           text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.advance_open_course_offerings_to_release (
  p_course_definition_release_id uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."advance_open_course_offerings_to_release"(uuid) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.branch_course_offering (
  p_offering_key                 text,
  p_course_definition_release_id uuid,
  p_code                         text,
  p_owner_profile_id             uuid,
  p_starts_at                    timestamp with time zone               DEFAULT NULL::timestamp WITH time zone,
  p_ends_at                      timestamp with time zone               DEFAULT NULL::timestamp WITH time zone,
  p_external_url                 text                                   DEFAULT NULL::text,
  p_membership_verification      private.course_membership_verification DEFAULT 'external_membership'::private.course_membership_verification
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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
    membership_verification,
    starts_at,
    ends_at,
    external_url
  )
  values (
    p_offering_key,
    v_course_definition_key,
    p_course_definition_release_id,
    p_code,
    p_membership_verification,
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

ALTER FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp
  WITH time zone, text, private.course_membership_verification) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.can_view_profile (
  p_profile_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."can_view_profile"(uuid) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.claim_course_repository_provisioning (
  p_limit         integer DEFAULT 25,
  p_course_id     uuid    DEFAULT NULL::uuid,
  p_profile_id    uuid    DEFAULT NULL::uuid,
  p_provider_kind text    DEFAULT NULL::text
)
  RETURNS TABLE (
    course_id               uuid,
    profile_id              uuid,
    access_request_id       uuid,
    offering_key            text,
    provider_kind           text,
    provider_issuer         text,
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
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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
      organization.provider_issuer,
      repository.external_group_id,
      repository.external_group_handle,
      repository.external_repository_id,
      repository.external_repository_url,
      resolved_identity.external_user_id,
      resolved_identity.external_user_handle,
      case
        when resolved_identity.external_user_handle is null then null
        when char_length('submissions-' || course.offering_key || '-' || resolved_identity.external_user_handle) <= 100
          then 'submissions-' || course.offering_key || '-' || resolved_identity.external_user_handle
        else
          'submissions-' || left(course.offering_key, 58) || '-' ||
          right(md5(course.offering_key || ':' || resolved_identity.external_user_handle), 8) || '-' ||
          left(resolved_identity.external_user_handle, 20)
      end as generated_repository_name
    from private.course_repository_provisioning as repository
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
     and course.course_definition_key = repository.course_definition_key
    join private.course_definition_external_groups as organization
      on organization.course_definition_key = repository.course_definition_key
    left join private.external_course_access as access_row
      on access_row.course_id = repository.course_id
     and access_row.profile_id = repository.profile_id
     and access_row.access_request_id = repository.access_request_id
     and access_row.external_group_id = repository.external_group_id
     and access_row.external_group_handle = repository.external_group_handle
    left join lateral (
      select
        -- The membership mode is the source-of-truth boundary. An external
        -- membership snapshot must not override a first-party profile fact,
        -- and an unexpected stale access row must not override approval-only
        -- provisioning.
        case
          when course.membership_verification = 'external_membership'
            then access_row.external_user_id
          when course.membership_verification = 'approval_only'
            then private.unique_active_profile_identifier(
              repository.profile_id,
              'external_user_id',
              organization.provider_issuer
            )
          else null
        end as external_user_id,
        case
          when course.membership_verification = 'external_membership'
            then access_row.external_user_handle
          when course.membership_verification = 'approval_only'
            then private.unique_active_profile_identifier(
              repository.profile_id,
              'external_user_handle',
              organization.provider_issuer
            )
          else null
        end as external_user_handle
    ) as resolved_identity on true
    where request_row.status = 'approved'
      and (
        course.membership_verification = 'approval_only'
        or (
          access_row.state = 'active'
          and access_row.external_user_handle is not null
          and access_row.failure_code is null
          and access_row.last_checked_at >= clock_timestamp() - interval '5 minutes'
        )
      )
      and resolved_identity.external_user_id is not null
      and resolved_identity.external_user_handle is not null
      and (p_course_id is null or repository.course_id = p_course_id)
      and (p_profile_id is null or repository.profile_id = p_profile_id)
      and (p_provider_kind is null or organization.provider_kind = p_provider_kind)
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
    organization.provider_issuer,
    claimed.external_group_id,
    claimed.external_group_handle,
    claimed.repository_name,
    claimed.external_repository_id,
    claimed.external_repository_url,
    resolved_identity.external_user_handle,
    resolved_identity.external_user_id,
    claimed.lease_token,
    claimed.attempt_count
  from claimed
  join public.courses as course on course.id = claimed.course_id
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  left join private.external_course_access as access_row
    on access_row.course_id = claimed.course_id
   and access_row.profile_id = claimed.profile_id
   and access_row.access_request_id = claimed.access_request_id
   and access_row.external_group_id = claimed.external_group_id
   and access_row.external_group_handle = claimed.external_group_handle
  left join lateral (
    select
      case
        when course.membership_verification = 'external_membership'
          then access_row.external_user_id
        when course.membership_verification = 'approval_only'
          then private.unique_active_profile_identifier(
            claimed.profile_id,
            'external_user_id',
            organization.provider_issuer
          )
        else null
      end as external_user_id,
      case
        when course.membership_verification = 'external_membership'
          then access_row.external_user_handle
        when course.membership_verification = 'approval_only'
          then private.unique_active_profile_identifier(
            claimed.profile_id,
            'external_user_handle',
            organization.provider_issuer
          )
        else null
      end as external_user_handle
  ) as resolved_identity on true
  ;
end
$function$;

ALTER FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.complete_course_repository_provisioning (
  p_course_id               uuid,
  p_profile_id              uuid,
  p_lease_token             uuid,
  p_external_repository_id  text,
  p_repository_name         text,
  p_external_repository_url text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.confirm_external_course_access (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_external_group_id      text,
  p_external_group_handle  text,
  p_external_invitation_id text,
  p_external_user_id       text,
  p_external_user_handle   text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_provider_issuer text;
  v_membership_verification private.course_membership_verification;
begin
  if p_external_group_id is null
    or p_external_group_id <> btrim(p_external_group_id)
    or char_length(p_external_group_id) not between 1 and 255
    or p_external_group_handle is null
    or p_external_group_handle <> btrim(p_external_group_handle)
    or char_length(p_external_group_handle) not between 1 and 255
    or (p_external_invitation_id is not null and (
      p_external_invitation_id <> btrim(p_external_invitation_id)
      or char_length(p_external_invitation_id) not between 1 and 255
    ))
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
         organization.provider_issuer,
         course.membership_verification
  into v_expected_external_group_id,
       v_expected_external_group_handle,
       v_provider_issuer,
       v_membership_verification
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id
    and course.status = 'published'
  for update of course;

  if not found then
    raise exception using errcode = '55000', message = 'course_offering_not_reconcilable';
  end if;

  if v_membership_verification <> 'external_membership' then
    raise exception using errcode = '42501', message = 'external_access_not_required';
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

  if v_access.external_invitation_id is distinct from p_external_invitation_id
  then
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

  perform private.activate_course_membership_from_request(
    v_request.id,
    case when p_external_invitation_id is null
      then 'Existing platform organization membership confirmed'
      else 'Platform organization invitation and membership confirmed'
    end
  );

end
$function$;

ALTER FUNCTION "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.current_profile_id()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."current_profile_id"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.ensure_auth_user_profile (
  p_auth_user_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."ensure_auth_user_profile"(uuid) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.handle_auth_identity_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform private.sync_auth_identity(new.id);
  return new;
end
$function$;

ALTER FUNCTION "private"."handle_auth_identity_changed"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.handle_auth_user_created()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform private.ensure_auth_user_profile(new.id);
  return new;
end
$function$;

ALTER FUNCTION "private"."handle_auth_user_created"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.has_course_role (
  p_course_id uuid,
  p_roles     private.course_membership_role[]
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."has_course_role"(uuid, private.course_membership_role[]) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.reconcile_auth_identities()
  RETURNS TABLE (
    auth_identity_id uuid,
    status           text,
    detail           text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_identity_id uuid;
begin
  for v_identity_id in
    select identity_row.id
    from private.auth_identities as identity_row
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

ALTER FUNCTION "private"."reconcile_auth_identities"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.reconcile_auth_users()
  RETURNS TABLE (
    auth_user_id uuid,
    profile_id   uuid,
    action       text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."reconcile_auth_users"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.record_course_repository_provisioning_failure (
  p_course_id   uuid,
  p_profile_id  uuid,
  p_lease_token uuid,
  p_error_code  text,
  p_retryable   boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.record_external_course_access_check_failure (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_failure_code text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."record_external_course_access_check_failure"(uuid, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.record_external_course_access_invitation (
  p_course_id              uuid,
  p_profile_id             uuid,
  p_invitation_method      private.external_invitation_method,
  p_invitation_target      text,
  p_external_invitation_id text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_access private.external_course_access%rowtype;
  v_expected_target text;
  v_expected_external_group_id text;
  v_expected_external_group_handle text;
  v_email_domain text;
  v_email_domain_enforced boolean;
  v_email_domain_allowed boolean;
  v_membership_verification private.course_membership_verification;
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

  select course.membership_verification
  into v_membership_verification
  from public.courses as course
  where course.id = p_course_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'course_not_found';
  end if;

  if v_membership_verification <> 'external_membership' then
    raise exception using errcode = '42501', message = 'external_access_not_required';
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

ALTER FUNCTION "private"."record_external_course_access_invitation"(uuid, uuid, private.external_invitation_method, text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.record_external_course_access_membership_absence (
  p_course_id  uuid,
  p_profile_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."record_external_course_access_membership_absence"(uuid, uuid) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.record_external_course_access_status (
  p_course_id    uuid,
  p_profile_id   uuid,
  p_state        private.external_course_access_state,
  p_failure_code text                                 DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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
      'External provider group membership no longer active'
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
          and event_row.reason = 'External provider group membership no longer active'
      );
  end if;
end
$function$;

ALTER FUNCTION "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.register_course_definition_release (
  p_course_definition_key text,
  p_source_commit_sha     text,
  p_course_release_digest text,
  p_artifact_ref          text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."register_course_definition_release"(text, text, text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.reject_mutation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception using
    errcode = '55000',
    message = format('%I.%I is append-only', tg_table_schema, tg_table_name);
end
$function$;

CREATE OR REPLACE FUNCTION private.request_auth_user_id()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
BEGIN ATOMIC
 SELECT auth.uid()
  AS uid;
END;

CREATE OR REPLACE FUNCTION private.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  new.updated_at := clock_timestamp();
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.sync_auth_identity (
  p_identity_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_identity record;
  v_profile_id uuid;
  v_provider_issuer text;
  v_external_user_id text;
  v_username text;
  v_username_candidates text[];
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

  v_external_user_id := btrim(coalesce(v_identity.provider_id, ''));
  if v_external_user_id = '' then
    raise exception using errcode = '22023', message = 'external_subject_required';
  end if;

  v_provider_issuer := btrim(coalesce(
    nullif(btrim(v_identity.identity_data ->> 'iss'), ''),
    v_identity.provider
  ));
  if v_provider_issuer = '' then
    raise exception using errcode = '22023', message = 'identity_issuer_required';
  end if;

  perform private.upsert_verified_identifier(
    v_profile_id,
    'external_user_id',
    v_provider_issuer,
    1,
    v_external_user_id,
    coalesce(v_identity.created_at, clock_timestamp()),
    v_identity.user_id,
    v_identity.id::text
  );

  select array_agg(distinct lower(btrim(candidate)))
  into v_username_candidates
  from unnest(array[
    v_identity.identity_data ->> 'preferred_username',
    v_identity.identity_data ->> 'user_name',
    v_identity.identity_data ->> 'login',
    v_identity.identity_data ->> 'username'
  ]) as candidate(candidate)
  where nullif(btrim(candidate), '') is not null
    and btrim(candidate) !~ '[[:space:]]';

  if cardinality(v_username_candidates) > 1 then
    raise exception using errcode = '22023', message = 'ambiguous_external_user_handle';
  end if;

  v_username := v_username_candidates[1];

  if nullif(v_username, '') is not null and v_username !~ '[[:space:]]' then
    update private.profile_identifiers
    set revoked_at = clock_timestamp(),
        last_verified_at = clock_timestamp()
    where profile_id = v_profile_id
      and kind = 'external_user_handle'
      and issuer = v_provider_issuer
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'external_user_handle',
      v_provider_issuer,
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
        and issuer = v_provider_issuer
        and scheme_version = 1
        and normalized_value <> v_email
        and revoked_at is null;

      perform private.upsert_verified_identifier(
        v_profile_id,
        'email',
        v_provider_issuer,
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

ALTER FUNCTION "private"."sync_auth_identity"(uuid) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.transfer_course_ownership (
  p_course_id            uuid,
  p_new_owner_profile_id uuid,
  p_actor_profile_id     uuid,
  p_reason               text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."transfer_course_ownership"(uuid, uuid, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.transition_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_new_role         private.course_membership_role,
  p_new_status       private.course_membership_status,
  p_actor_profile_id uuid,
  p_reason           text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.unique_active_profile_identifier (
  p_profile_id uuid,
  p_kind       text,
  p_issuer     text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select min(identifier.normalized_value)
  from private.profile_identifiers as identifier
  where identifier.profile_id = p_profile_id
    and identifier.kind = p_kind
    and (p_issuer is null or identifier.issuer = p_issuer)
    and identifier.revoked_at is null
  having count(*) = 1
$function$;

CREATE OR REPLACE FUNCTION private.list_external_course_access_to_reconcile()
  RETURNS TABLE (
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
    invitation_method              private.external_invitation_method,
    invitation_target              text,
    state                          private.external_course_access_state
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 SELECT access_row.course_id,
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
     access_row.state
    FROM ((((private.external_course_access access_row
      JOIN private.course_access_requests request_row
        ON (((request_row.id = access_row.access_request_id) AND (request_row.course_id = access_row.course_id) AND (request_row.requester_profile_id = access_row.profile_id))))
      JOIN public.courses course ON ((course.id = access_row.course_id)))
      JOIN private.course_definition_external_groups organization ON ((organization.course_definition_key = course.course_definition_key)))
      LEFT JOIN LATERAL ( SELECT private.unique_active_profile_identifier(access_row.profile_id, 'email'::text, organization.provider_issuer) AS normalized_value) email ON (true))
   WHERE
     ((request_row.status = 'approved'::private.course_access_request_status) AND (course.status = 'published'::private.course_offering_status) AND (course.membership_verification
     = 'external_membership'::private.course_membership_verification) AND (access_row.state <> 'revoked'::private.external_course_access_state));
END;

ALTER FUNCTION "private"."list_external_course_access_to_reconcile"() OWNER TO "ainigma_function_owner";

ALTER FUNCTION "private"."unique_active_profile_identifier"(uuid, text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION private.upsert_verified_identifier (
  p_profile_id           uuid,
  p_kind                 text,
  p_issuer               text,
  p_scheme_version       integer,
  p_normalized_value     text,
  p_verified_at          timestamp with time zone,
  p_source_auth_user_id  uuid,
  p_provider_identity_id text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "private"."upsert_verified_identifier"(uuid, text, text, integer, text, timestamp WITH time zone, uuid, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.approve_course_access_requests (
  p_offering_key text,
  p_request_ids  uuid[] DEFAULT NULL::uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_course_id uuid;
  v_actor_profile_id uuid := private.current_profile_id();
  v_count integer;
  v_provider_issuer text;
  v_membership_verification private.course_membership_verification;
  v_changed_request_ids uuid[];
  v_request_id uuid;
begin
  select course.id, organization.provider_issuer, course.membership_verification
  into v_course_id, v_provider_issuer, v_membership_verification
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
  for update of course;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::private.course_membership_role[]) then
    raise sqlstate 'PT404' using message = 'course_not_found';
  end if;

  if p_request_ids is not null and exists (
    select 1 from private.course_access_requests as request_row
    where request_row.id = any (p_request_ids) and request_row.course_id <> v_course_id
  ) then
    raise sqlstate 'PT400' using message = 'request_course_mismatch';
  end if;

  if v_membership_verification = 'external_membership'
    and exists (
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
  select coalesce(array_agg(changed.id), '{}'::uuid[])
  into v_changed_request_ids
  from changed;

  v_count := cardinality(v_changed_request_ids);

  if v_membership_verification = 'approval_only' then
    foreach v_request_id in array v_changed_request_ids loop
      perform private.activate_course_membership_from_request(
        v_request_id,
        'Course access request approved by owner'
      );
    end loop;
  else
    insert into private.external_course_access (course_id, profile_id, access_request_id, external_user_id, state)
    select request_row.course_id,
           request_row.requester_profile_id,
           request_row.id,
           identifier.normalized_value,
           'not_started'
    from private.course_access_requests as request_row
    join private.profile_identifiers as identifier
      on identifier.profile_id = request_row.requester_profile_id
     and identifier.kind = 'external_user_id'
     and identifier.issuer = v_provider_issuer
     and identifier.revoked_at is null
    where request_row.id = any (v_changed_request_ids)
    on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;
  end if;

  return v_count;
end
$function$;

ALTER FUNCTION "public"."approve_course_access_requests"(text, uuid[]) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.get_my_course_repository (
  p_offering_key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "public"."get_my_course_repository"(text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.get_my_profile()
  RETURNS TABLE (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 SELECT profile.display_name,
     profile.created_at,
     profile.updated_at
    FROM public.profiles profile
   WHERE (profile.id = private.current_profile_id());
END;

ALTER FUNCTION "public"."get_my_profile"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.list_available_courses()
  RETURNS TABLE (
    offering_key                 text,
    course_definition_key        text,
    course_definition_release_id uuid,
    code                         text,
    enrollment_mode              text,
    starts_at                    timestamp with time zone,
    ends_at                      timestamp with time zone,
    external_url                 text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "public"."list_available_courses"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.list_course_access_requests (
  p_offering_key         text,
  p_status               private.course_access_request_status DEFAULT 'pending'::private.course_access_request_status,
  p_authorization_filter text                                 DEFAULT NULL::text
)
  RETURNS TABLE (
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
    external_access_state private.external_course_access_state
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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
    private.unique_active_profile_identifier(
      request_row.requester_profile_id,
      'external_user_handle',
      v_provider_issuer
    ),
    private.unique_active_profile_identifier(
      request_row.requester_profile_id,
      'email',
      null
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
    access_row.state
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

ALTER FUNCTION "public"."list_course_access_requests"(text, private.course_access_request_status, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.list_course_roster (
  p_offering_key text
)
  RETURNS TABLE (
    display_name text,
    role         private.course_membership_role,
    status       private.course_membership_status,
    created_at   timestamp with time zone,
    suspended_at timestamp with time zone,
    revoked_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "public"."list_course_roster"(text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.list_my_course_access_requests()
  RETURNS TABLE (
    offering_key          text,
    request_id            uuid,
    status                private.course_access_request_status,
    reason                text,
    requested_at          timestamp with time zone,
    decided_at            timestamp with time zone,
    external_access_state private.external_course_access_state
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 SELECT course.offering_key,
     request_row.id,
     request_row.status,
     request_row.reason,
     request_row.requested_at,
     request_row.decided_at,
     access_row.state
    FROM ((private.course_access_requests request_row
      JOIN public.courses course ON ((course.id = request_row.course_id)))
      LEFT JOIN private.external_course_access access_row ON ((access_row.access_request_id = request_row.id)))
   WHERE (request_row.requester_profile_id = private.current_profile_id())
   ORDER BY request_row.requested_at DESC;
END;

ALTER FUNCTION "public"."list_my_course_access_requests"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.list_my_courses()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 SELECT
   jsonb_build_object('courses', COALESCE(( SELECT jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_key', course.course_definition_key,
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
   'ends_at', course.ends_at, 'external_url', course.external_url, 'created_at', course.created_at, 'updated_at', course.updated_at) ORDER BY course.offering_key) AS jsonb_agg
            FROM (public.courses course
              JOIN public.course_memberships membership ON ((membership.course_id = course.id)))
           WHERE
             ((membership.profile_id = private.current_profile_id()) AND (membership.status = 'active'::private.course_membership_status) AND ((course.status = ANY
             (ARRAY['published'::private.course_offering_status, 'archived'::private.course_offering_status])) OR
             ((course.status = 'draft'::private.course_offering_status) AND (membership.role = ANY (ARRAY['owner'::private.course_membership_role,
             'instructor'::private.course_membership_role])))))),
             '[]'::jsonb),
             'inactive_memberships',
             COALESCE(( SELECT jsonb_agg(jsonb_build_object('offering_key', course.offering_key, 'course_definition_release_id', course.course_definition_release_id,
             'course_status',
             course.status,
             'membership_role',
             membership.role,
             'membership_status',
             membership.status,
             'created_at', membership.created_at, 'suspended_at', membership.suspended_at, 'revoked_at', membership.revoked_at) ORDER BY course.offering_key) AS jsonb_agg
            FROM (public.courses course
              JOIN public.course_memberships membership ON ((membership.course_id = course.id)))
           WHERE
             ((membership.profile_id = private.current_profile_id()) AND (NOT ((membership.status = 'active'::private.course_membership_status) AND ((course.status = ANY
             (ARRAY['published'::private.course_offering_status, 'archived'::private.course_offering_status])) OR
             ((course.status = 'draft'::private.course_offering_status) AND (membership.role = ANY (ARRAY['owner'::private.course_membership_role,
             'instructor'::private.course_membership_role])))))))), '[]'::jsonb))
  AS jsonb_build_object;
END;

ALTER FUNCTION "public"."list_my_courses"() OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.reject_course_access_requests (
  p_offering_key    text,
  p_request_ids     uuid[] DEFAULT NULL::uuid[],
  p_decision_reason text   DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
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

ALTER FUNCTION "public"."reject_course_access_requests"(text, uuid[], text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.request_course_access (
  p_offering_key text,
  p_reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_enrollment_mode text;
  v_membership_verification private.course_membership_verification;
  v_provider_issuer text;
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id,
         course.enrollment_mode::text,
         course.membership_verification,
         organization.provider_issuer
  into v_course_id, v_enrollment_mode, v_membership_verification, v_provider_issuer
  from public.courses as course
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published'
  for update of course;

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
      'state', case
        when v_request.status = 'approved'
          and v_membership_verification = 'external_membership'
          then 'awaiting_external_access'
        when v_request.status = 'approved' then 'active'
        else 'pending'
      end,
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
    and (
      v_membership_verification = 'approval_only'
      or exists (
        select 1
        from private.profile_identifiers as identifier
        where identifier.profile_id = v_profile_id
          and identifier.kind = 'external_user_id'
          and identifier.issuer = v_provider_issuer
          and identifier.revoked_at is null
      )
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
    if v_membership_verification = 'approval_only' then
      perform private.activate_course_membership_from_request(
        v_request.id,
        'Course access request approved from allowlist'
      );

      return jsonb_build_object(
        'state', 'active',
        'offering_key', p_offering_key,
        'request_id', v_request.id
      );
    end if;

    insert into private.external_course_access (
      course_id, profile_id, access_request_id, external_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      private.unique_active_profile_identifier(
        v_profile_id,
        'external_user_id',
        v_provider_issuer
      ),
      'not_started'
    where private.unique_active_profile_identifier(
      v_profile_id,
      'external_user_id',
      v_provider_issuer
    ) is not null;

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

ALTER FUNCTION "public"."request_course_access"(text, text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.request_my_course_repository (
  p_offering_key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
  v_access_request_id uuid;
  v_course_definition_key text;
  v_external_group_id text;
  v_external_group_handle text;
begin
  select
    course.id,
    course.course_definition_key,
    request_row.id,
    organization.external_group_id,
    organization.external_group_handle
  into
    v_course_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  from public.courses as course
  join public.course_memberships as membership
    on membership.course_id = course.id
   and membership.profile_id = v_profile_id
   and membership.role = 'learner'
   and membership.status = 'active'
  join private.course_access_requests as request_row
    on request_row.course_id = course.id
   and request_row.requester_profile_id = v_profile_id
   and request_row.id = membership.created_from_access_request_id
   and request_row.status = 'approved'
  join private.course_definition_external_groups as organization
    on organization.course_definition_key = course.course_definition_key
  where course.offering_key = p_offering_key
    and course.status = 'published'
    and (
      course.membership_verification = 'approval_only'
      or exists (
        select 1
        from private.external_course_access as access_row
        where access_row.course_id = course.id
          and access_row.profile_id = v_profile_id
          and access_row.state = 'active'
          and access_row.external_group_id = organization.external_group_id
          and access_row.external_group_handle = organization.external_group_handle
      )
    )
  for update of course;

  if v_course_id is null then
    raise sqlstate 'PT403' using message = 'course_repository_request_not_allowed';
  end if;

  insert into private.course_repository_provisioning (
    course_id,
    profile_id,
    course_definition_key,
    access_request_id,
    external_group_id,
    external_group_handle
  ) values (
    v_course_id,
    v_profile_id,
    v_course_definition_key,
    v_access_request_id,
    v_external_group_id,
    v_external_group_handle
  )
  on conflict (course_id, profile_id) do nothing;

  return public.get_my_course_repository(p_offering_key);
end
$function$;

ALTER FUNCTION "public"."request_my_course_repository"(text) OWNER TO "ainigma_function_owner";

CREATE OR REPLACE FUNCTION public.update_my_profile (
  p_display_name text
)
  RETURNS TABLE (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 UPDATE public.profiles profile
  SET display_name = update_my_profile.p_display_name
   WHERE (profile.id = private.current_profile_id())
   RETURNING profile.display_name,
     profile.created_at,
     profile.updated_at;
END;

ALTER FUNCTION "public"."update_my_profile"(text) OWNER TO "ainigma_function_owner";

ALTER TABLE "private"."auth_user_links"
  ADD CONSTRAINT "auth_user_links_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "private"."course_access_requests"
  ADD CONSTRAINT "course_access_requests_decision_shape_check"
    CHECK
    ((((status = ANY (ARRAY['pending'::private.course_access_request_status, 'cancelled'::private.course_access_request_status])) AND (decided_at IS NULL) AND (decided_by IS NULL))
    OR ((status = 'approved'::private.course_access_request_status) AND (decided_at IS NOT NULL) AND ((decided_by IS
    NOT NULL) OR (decision_source = 'allowlist'::text))) OR ((status = 'rejected'::private.course_access_request_status) AND (decided_at IS NOT NULL) AND (decided_by IS
    NOT NULL) AND (decision_source = 'owner'::text))));

ALTER TABLE "private"."course_definition_external_email_domains"
  ADD CONSTRAINT "course_definition_external_email_dom_course_definition_key_fkey" FOREIGN KEY (course_definition_key)
    REFERENCES private.course_definition_external_groups(course_definition_key) ON DELETE CASCADE;

ALTER TABLE "private"."course_definition_releases"
  ADD CONSTRAINT "course_definition_releases_external_group_fkey" FOREIGN KEY (course_definition_key) REFERENCES private.course_definition_external_groups(course_definition_key)
    ON DELETE RESTRICT;

ALTER TABLE "private"."course_membership_events"
  ADD CONSTRAINT "course_membership_events_shape_check"
    CHECK ((((event_kind = 'created'::text) AND (previous_role IS NULL) AND (previous_status IS NULL)) OR ((event_kind = 'transitioned'::text) AND (previous_role IS
    NOT NULL) AND (previous_status IS NOT NULL))));

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_access_request_fkey" FOREIGN KEY (access_request_id, course_id, profile_id)
    REFERENCES private.course_access_requests(id, course_id, requester_profile_id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_repository_target_fkey" FOREIGN KEY (course_definition_key, external_group_id, external_group_handle)
    REFERENCES private.course_definition_external_groups(course_definition_key, external_group_id, external_group_handle) ON DELETE RESTRICT;

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_group_shape_check"
    CHECK
    ((((state = 'not_started'::private.external_course_access_state) AND (external_group_id IS NULL) AND (external_group_handle IS NULL)) OR ((state <>
    'not_started'::private.external_course_access_state) AND (external_group_id IS NOT NULL) AND (external_group_handle IS NOT NULL))));

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_request_course_profile_fk" FOREIGN KEY (access_request_id, course_id, profile_id)
    REFERENCES private.course_access_requests(id, course_id, requester_profile_id) ON DELETE RESTRICT;

ALTER TABLE "private"."profile_identifiers"
  ADD CONSTRAINT "profile_identifiers_source_auth_user_id_fkey" FOREIGN KEY (source_auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."course_memberships"
  ADD CONSTRAINT "course_memberships_access_request_fk" FOREIGN KEY (created_from_access_request_id) REFERENCES private.course_access_requests(id) ON DELETE RESTRICT;

ALTER TABLE "public"."course_memberships"
  ADD CONSTRAINT "course_memberships_owner_status_check" CHECK (((role <> 'owner'::private.course_membership_role) OR (status = 'active'::private.course_membership_status)));

ALTER TABLE "public"."course_memberships"
  ADD CONSTRAINT "course_memberships_status_timestamps_check"
    CHECK
    ((((status = 'active'::private.course_membership_status) AND (suspended_at IS NULL) AND (revoked_at IS NULL)) OR ((status = 'suspended'::private.course_membership_status) AND
    (suspended_at IS NOT NULL) AND (revoked_at IS NULL)) OR ((status = 'revoked'::private.course_membership_status) AND (revoked_at IS NOT NULL))));

ALTER TABLE "public"."courses"
  ADD CONSTRAINT "courses_course_definition_external_group_fkey" FOREIGN KEY (course_definition_key) REFERENCES private.course_definition_external_groups(course_definition_key)
    ON DELETE RESTRICT;

ALTER TABLE "public"."courses"
  ADD CONSTRAINT "courses_course_definition_release_fkey" FOREIGN KEY (course_definition_release_id, course_definition_key)
    REFERENCES private.course_definition_releases(id, course_definition_key) ON DELETE RESTRICT;

ALTER TABLE "private"."course_repository_provisioning"
  ADD CONSTRAINT "course_repository_provisioning_course_definition_fkey" FOREIGN KEY (course_id, course_definition_key) REFERENCES public.courses(id, course_definition_key)
    ON DELETE RESTRICT;

ALTER TABLE "private"."course_access_requests"
  ADD CONSTRAINT "course_access_requests_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_membership_events"
  ADD CONSTRAINT "course_membership_events_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_roster_allowlist"
  ADD CONSTRAINT "course_roster_allowlist_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;

ALTER TABLE "public"."course_memberships"
  ADD CONSTRAINT "course_memberships_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;

ALTER TABLE "private"."auth_user_links"
  ADD CONSTRAINT "auth_user_links_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_access_requests"
  ADD CONSTRAINT "course_access_requests_decided_by_fkey" FOREIGN KEY (decided_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_access_requests"
  ADD CONSTRAINT "course_access_requests_requester_profile_id_fkey" FOREIGN KEY (requester_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_membership_events"
  ADD CONSTRAINT "course_membership_events_actor_profile_id_fkey" FOREIGN KEY (actor_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_membership_events"
  ADD CONSTRAINT "course_membership_events_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."course_roster_allowlist"
  ADD CONSTRAINT "course_roster_allowlist_imported_by_fkey" FOREIGN KEY (imported_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."external_course_access"
  ADD CONSTRAINT "external_course_access_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "private"."profile_identifiers"
  ADD CONSTRAINT "profile_identifiers_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."course_memberships"
  ADD CONSTRAINT "course_memberships_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;

CREATE VIEW "private"."auth_identities" AS  SELECT id,
    user_id,
    provider_id,
    provider,
    identity_data,
    created_at,
    updated_at
   FROM auth.identities identity_row;

CREATE OR REPLACE FUNCTION private.report_identity_anomalies()
  RETURNS TABLE (
    anomaly          text,
    profile_id       uuid,
    auth_user_id     uuid,
    auth_identity_id uuid,
    detail           text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
BEGIN ATOMIC
 SELECT 'orphan_profile'::text
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

ALTER FUNCTION "private"."report_identity_anomalies"() OWNER TO "ainigma_function_owner";

CREATE VIEW "private"."auth_users" AS  SELECT id,
    created_at,
    deleted_at
   FROM auth.users auth_user;

CREATE INDEX auth_user_links_profile_id_idx ON private.auth_user_links USING btree (profile_id);

CREATE INDEX course_access_requests_course_status_idx ON private.course_access_requests USING btree (course_id, status, requested_at);

CREATE UNIQUE INDEX course_access_requests_pending_uidx ON private.course_access_requests USING btree (course_id, requester_profile_id)
  WHERE (status = 'pending'::private.course_access_request_status);

CREATE INDEX course_definition_external_groups_group_id_idx ON private.course_definition_external_groups USING btree (external_group_id);

CREATE INDEX course_definition_releases_latest_idx ON private.course_definition_releases USING btree (course_definition_key, created_at DESC, id);

CREATE INDEX course_membership_events_course_created_idx ON private.course_membership_events USING btree (course_id, created_at DESC);

CREATE INDEX course_membership_events_profile_created_idx ON private.course_membership_events USING btree (profile_id, created_at DESC);

CREATE INDEX course_repository_provisioning_claim_idx ON private.course_repository_provisioning USING btree (state, next_attempt_at, lease_expires_at, updated_at);

CREATE UNIQUE INDEX course_repository_provisioning_org_name_uidx ON private.course_repository_provisioning USING btree (external_group_id, repository_name)
  WHERE (repository_name IS NOT NULL);

CREATE UNIQUE INDEX course_repository_provisioning_repository_id_uidx ON private.course_repository_provisioning USING btree (external_repository_id)
  WHERE (external_repository_id IS NOT NULL);

CREATE UNIQUE INDEX course_roster_allowlist_active_uidx ON private.course_roster_allowlist
  USING btree (course_id, identifier_kind, identifier_issuer, identifier_scheme_version, normalized_identifier_value)
  WHERE (status = 'active'::text);

CREATE INDEX course_roster_allowlist_course_idx ON private.course_roster_allowlist USING btree (course_id, status);

CREATE UNIQUE INDEX external_course_access_request_uidx ON private.external_course_access USING btree (access_request_id);

CREATE UNIQUE INDEX profile_identifiers_active_external_user_uidx ON private.profile_identifiers USING btree (profile_id, issuer, scheme_version)
  WHERE ((kind = 'external_user_id'::text) AND (revoked_at IS NULL));

CREATE UNIQUE INDEX profile_identifiers_active_identity_uidx ON private.profile_identifiers USING btree (kind, issuer, scheme_version, normalized_value)
  WHERE (revoked_at IS NULL);

CREATE UNIQUE INDEX profile_identifiers_active_provider_fact_uidx ON private.profile_identifiers USING btree (profile_id, kind, issuer, scheme_version)
  WHERE ((kind = ANY (ARRAY['email'::text, 'external_user_handle'::text])) AND (revoked_at IS NULL));

CREATE INDEX profile_identifiers_profile_active_idx ON private.profile_identifiers USING btree (profile_id, kind, issuer, scheme_version)
  WHERE (revoked_at IS NULL);

CREATE INDEX profile_identifiers_source_auth_user_idx ON private.profile_identifiers USING btree (source_auth_user_id)
  WHERE (source_auth_user_id IS NOT NULL);

CREATE UNIQUE INDEX course_memberships_access_request_uidx ON public.course_memberships USING btree (created_from_access_request_id)
  WHERE (created_from_access_request_id IS NOT NULL);

CREATE INDEX course_memberships_course_role_status_idx ON public.course_memberships USING btree (course_id, ROLE, status);

CREATE UNIQUE INDEX course_memberships_one_active_owner_uidx ON public.course_memberships USING btree (course_id)
  WHERE ((ROLE = 'owner'::private.course_membership_role) AND (status = 'active'::private.course_membership_status));

CREATE INDEX course_memberships_profile_status_role_idx ON public.course_memberships USING btree (profile_id, status, ROLE, course_id);

CREATE INDEX courses_course_definition_key_idx ON public.courses USING btree (course_definition_key);

CREATE INDEX courses_course_definition_release_id_idx ON public.courses USING btree (course_definition_release_id);

CREATE INDEX courses_status_window_idx ON public.courses USING btree (status, starts_at, ends_at);

CREATE TRIGGER on_auth_identity_changed
  AFTER INSERT OR UPDATE OF provider_id, identity_data, PROVIDER ON auth.identities
  FOR EACH ROW
  EXECUTE FUNCTION private.handle_auth_identity_changed();

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.handle_auth_user_created();

CREATE TRIGGER course_definition_releases_reject_mutation
  BEFORE DELETE OR UPDATE ON private.course_definition_releases
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_mutation();

CREATE TRIGGER course_membership_events_reject_mutation
  BEFORE DELETE OR UPDATE ON private.course_membership_events
  FOR EACH ROW
  EXECUTE FUNCTION private.reject_mutation();

CREATE TRIGGER course_repository_provisioning_set_updated_at
  BEFORE UPDATE ON private.course_repository_provisioning
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER profile_identifiers_set_updated_at
  BEFORE UPDATE ON private.profile_identifiers
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER courses_set_updated_at
  BEFORE UPDATE ON public.courses
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE POLICY "course_access_requests_function_access" ON "private"."course_access_requests"
  FOR ALL
  TO "ainigma_function_owner", "ainigma_maintenance"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "course_repository_provisioning_function_access" ON "private"."course_repository_provisioning"
  FOR ALL
  TO "ainigma_function_owner", "ainigma_maintenance"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "course_roster_allowlist_function_access" ON "private"."course_roster_allowlist"
  FOR ALL
  TO "ainigma_function_owner", "ainigma_maintenance"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "external_course_access_function_access" ON "private"."external_course_access"
  FOR ALL
  TO "ainigma_function_owner", "ainigma_maintenance"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "course_memberships_function_owner_access" ON "public"."course_memberships"
  FOR ALL
  TO "ainigma_function_owner"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "course_memberships_select_authorized" ON "public"."course_memberships"
  FOR SELECT
  TO "authenticated"
  USING
    (((profile_id = ( SELECT private.current_profile_id() AS current_profile_id)) OR ( SELECT private.has_course_role(course_memberships.course_id,
    ARRAY['owner'::private.course_membership_role, 'instructor'::private.course_membership_role]) AS has_course_role)));

CREATE POLICY "courses_function_owner_access" ON "public"."courses"
  FOR ALL
  TO "ainigma_function_owner"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "courses_select_enrolled" ON "public"."courses"
  FOR SELECT
  TO "authenticated"
  USING
    ((((status = 'published'::private.course_offering_status) AND ( SELECT private.has_course_role(courses.id, ARRAY['owner'::private.course_membership_role,
    'instructor'::private.course_membership_role,
    'learner'::private.course_membership_role]) AS has_course_role)) OR
    ((status = 'draft'::private.course_offering_status) AND ( SELECT private.has_course_role(courses.id, ARRAY['owner'::private.course_membership_role,
    'instructor'::private.course_membership_role]) AS has_course_role))));

CREATE POLICY "profiles_function_owner_access" ON "public"."profiles"
  FOR ALL
  TO "ainigma_function_owner"
  USING (true)
  WITH CHECK (true);

CREATE POLICY "profiles_select_authorized" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.can_view_profile(profiles.id) AS can_view_profile));

CREATE POLICY "profiles_update_own_display_name" ON "public"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING ((id = ( SELECT private.current_profile_id() AS current_profile_id)))
  WITH CHECK ((id = ( SELECT private.current_profile_id() AS current_profile_id)));

COMMENT ON COLUMN "private"."course_definition_external_groups"."email_domain_enforced" IS 'Whether email invitation targets must match the configured domain suffixes.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."external_group_handle" IS 'Current provider group handle for diagnostics and display; external_group_id is authoritative.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."external_group_id" IS 'Stable provider group ID used for external membership verification when configured; the handle is only a display snapshot.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."provider_issuer" IS 'Trusted identity namespace used to select verified profile facts for this provider target.';

COMMENT ON COLUMN "private"."course_definition_external_groups"."provider_kind" IS 'Opaque provider adapter key used to route external membership and repository operations.';

COMMENT ON COLUMN "private"."course_definition_releases"."artifact_ref" IS 'Immutable deployable artifact reference resolved by the compiler and deployment system.';

COMMENT ON COLUMN "private"."course_repository_provisioning"."external_repository_id" IS 'Stable provider repository ID; used instead of the mutable repository name for reconciliation.';

COMMENT ON COLUMN "private"."course_repository_provisioning"."repository_name" IS 'Deterministic offering-specific repository name, normally submissions-<offering_key>-<user_handle>.';

COMMENT ON COLUMN "private"."external_course_access"."external_invitation_id" IS 'Provider invitation ID for the current invitation attempt; acceptance must match this ID.';

COMMENT ON COLUMN "private"."external_course_access"."external_user_handle" IS 'Current provider login or handle cached from verified membership; it may change and is not an identity key.';

COMMENT ON COLUMN "private"."external_course_access"."external_user_id" IS 'Stable external provider account ID. This is the identity key for the offering access record.';

COMMENT ON COLUMN "public"."courses"."course_definition_key" IS 'Immutable key of the reusable Git-authored course definition rendered for this offering.';

COMMENT ON COLUMN "public"."courses"."course_definition_release_id" IS 'Exact compiler release currently rendered for this offering; ended offerings stop advancing.';

COMMENT ON COLUMN "public"."courses"."membership_verification" IS 'Post-approval course membership gate: external_membership requires the configured provider group; approval_only relies on first-party identity and request approval.';

COMMENT ON COLUMN "public"."courses"."offering_key" IS 'Globally unique immutable key for one term, cohort, or operational course space.';

COMMENT ON FUNCTION "private"."unique_active_profile_identifier"(uuid, text, text) IS 'Returns one active profile identifier only when the requested provider fact is unambiguous.';

COMMENT ON TABLE "private"."course_definition_external_email_domains" IS 'Allowed email domain suffixes for invitations to a course definition.';

COMMENT ON TABLE "private"."course_definition_external_groups" IS 'The trusted external provider group configured for each reusable course definition.';

COMMENT ON TABLE "private"."course_definition_releases" IS 'Immutable Ainigma compiler outputs for reusable course definitions.';

COMMENT ON TABLE "private"."course_repository_provisioning" IS 'Durable idempotent outbox for one external submissions repository per offering and profile.';

COMMENT ON TABLE "public"."courses" IS 'Operational course offerings. Titles, navigation, and authored content remain in Git.';

COMMENT ON TABLE "public"."profiles" IS 'Provider-neutral application identities. Authorization claims remain private.';

REVOKE ALL ON FUNCTION "private"."activate_course_membership_from_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."activate_course_membership_from_request"(uuid, text) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."add_course_membership"(uuid, uuid, private.course_membership_role, uuid, text) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."advance_open_course_offerings_to_release"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."advance_open_course_offerings_to_release"(uuid) TO "ainigma_maintenance";

REVOKE ALL
  ON FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, private.course_membership_verification)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."branch_course_offering"(text, uuid, text, uuid, timestamp WITH time zone, timestamp WITH time zone, text, private.course_membership_verification)
  TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."can_view_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."can_view_profile"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."claim_course_repository_provisioning"(integer, uuid, uuid, text) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."complete_course_repository_provisioning"(uuid, uuid, uuid, text, text, text) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."confirm_external_course_access"(uuid, uuid, text, text, text, text, text) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."current_profile_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."current_profile_id"() TO "authenticated";

REVOKE ALL ON FUNCTION "private"."ensure_auth_user_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."ensure_auth_user_profile"(uuid) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."handle_auth_identity_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."handle_auth_user_created"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."has_course_role"(uuid, private.course_membership_role[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."has_course_role"(uuid, private.course_membership_role[]) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."list_external_course_access_to_reconcile"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."list_external_course_access_to_reconcile"() TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."reconcile_auth_identities"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."reconcile_auth_identities"() TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."reconcile_auth_users"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."reconcile_auth_users"() TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."record_course_repository_provisioning_failure"(uuid, uuid, uuid, text, boolean)
  TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."record_external_course_access_check_failure"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."record_external_course_access_check_failure"(uuid, uuid, text) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."record_external_course_access_invitation"(uuid, uuid, private.external_invitation_method, text, text) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."record_external_course_access_invitation"(uuid, uuid, private.external_invitation_method, text, text)
  TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."record_external_course_access_membership_absence"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."record_external_course_access_membership_absence"(uuid, uuid) TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."record_external_course_access_status"(uuid, uuid, private.external_course_access_state, text)
  TO "ainigma_external_provisioning_worker", "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."register_course_definition_release"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."register_course_definition_release"(text, text, text, text) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."reject_mutation"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."reject_mutation"() TO "postgres";

REVOKE ALL ON FUNCTION "private"."report_identity_anomalies"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."report_identity_anomalies"() TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."request_auth_user_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."request_auth_user_id"() TO "ainigma_function_owner", "postgres";

REVOKE ALL ON FUNCTION "private"."set_updated_at"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."set_updated_at"() TO "postgres";

REVOKE ALL ON FUNCTION "private"."sync_auth_identity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."sync_auth_identity"(uuid) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."transfer_course_ownership"(uuid, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."transfer_course_ownership"(uuid, uuid, uuid, text) TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "private"."transition_course_membership"(uuid, uuid, private.course_membership_role, private.course_membership_status, uuid, text)
  TO "ainigma_maintenance";

REVOKE ALL ON FUNCTION "private"."unique_active_profile_identifier"(uuid, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "private"."upsert_verified_identifier"(uuid, text, text, integer, text, timestamp WITH time zone, uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."approve_course_access_requests"(text, uuid[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."approve_course_access_requests"(text, uuid[]) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."approve_course_access_requests"(text, uuid[]) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."approve_course_access_requests"(text, uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."get_my_course_repository"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."get_my_course_repository"(text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."get_my_course_repository"(text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."get_my_course_repository"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."get_my_profile"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."get_my_profile"() FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."get_my_profile"() TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."get_my_profile"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."list_available_courses"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."list_available_courses"() FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_available_courses"() TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_available_courses"() TO "anon", "authenticated";

REVOKE ALL ON FUNCTION "public"."list_course_access_requests"(text, private.course_access_request_status, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."list_course_access_requests"(text, private.course_access_request_status, text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_course_access_requests"(text, private.course_access_request_status, text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_course_access_requests"(text, private.course_access_request_status, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."list_course_roster"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."list_course_roster"(text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_course_roster"(text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_course_roster"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."list_my_course_access_requests"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."list_my_course_access_requests"() FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_my_course_access_requests"() TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_my_course_access_requests"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."list_my_courses"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."list_my_courses"() FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_my_courses"() TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."list_my_courses"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."reject_course_access_requests"(text, uuid[], text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."reject_course_access_requests"(text, uuid[], text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."reject_course_access_requests"(text, uuid[], text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."reject_course_access_requests"(text, uuid[], text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."request_course_access"(text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."request_course_access"(text, text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."request_course_access"(text, text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."request_course_access"(text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."request_my_course_repository"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."request_my_course_repository"(text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."request_my_course_repository"(text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."request_my_course_repository"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_my_profile"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."update_my_profile"(text) FROM "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"(text) TO "ainigma_function_owner";

GRANT EXECUTE ON FUNCTION "public"."update_my_profile"(text) TO "authenticated";

REVOKE ALL ON SCHEMA "private" FROM "ainigma_external_provisioning_worker";

GRANT USAGE ON SCHEMA "private" TO "ainigma_external_provisioning_worker";

REVOKE ALL ON SCHEMA "private" FROM "ainigma_maintenance";

GRANT USAGE ON SCHEMA "private" TO "ainigma_maintenance";

GRANT INSERT, SELECT ON TABLE "private"."auth_user_links" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."auth_user_links" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "private"."course_access_requests" TO "ainigma_function_owner", "ainigma_maintenance";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_access_requests" TO "postgres";

GRANT SELECT ON TABLE "private"."course_definition_external_email_domains" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_definition_external_email_domains" TO "postgres";

GRANT SELECT ON TABLE "private"."course_definition_external_groups" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_definition_external_groups" TO "postgres";

GRANT INSERT, SELECT ON TABLE "private"."course_definition_releases" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_definition_releases" TO "postgres";

GRANT INSERT, SELECT ON TABLE "private"."course_membership_events" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_membership_events" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "private"."course_repository_provisioning" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_repository_provisioning" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "private"."course_roster_allowlist" TO "ainigma_function_owner", "ainigma_maintenance";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."course_roster_allowlist" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "private"."external_course_access" TO "ainigma_function_owner", "ainigma_maintenance";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."external_course_access" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "private"."profile_identifiers" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."profile_identifiers" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."course_memberships" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."course_memberships" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."courses" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."courses" TO "postgres";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."profiles" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";

GRANT USAGE ON TYPE "private"."course_access_request_status" TO "postgres";

GRANT USAGE ON TYPE "private"."course_enrollment_mode" TO "postgres";

GRANT USAGE ON TYPE "private"."course_membership_role" TO "postgres";

GRANT USAGE ON TYPE "private"."course_membership_status" TO "postgres";

GRANT USAGE ON TYPE "private"."course_membership_verification" TO "postgres";

GRANT USAGE ON TYPE "private"."course_offering_status" TO "postgres";

GRANT USAGE ON TYPE "private"."external_course_access_state" TO "postgres";

GRANT USAGE ON TYPE "private"."external_invitation_method" TO "postgres";

GRANT SELECT ON TABLE "private"."auth_identities" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."auth_identities" TO "postgres";

GRANT SELECT ON TABLE "private"."auth_users" TO "ainigma_function_owner";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "private"."auth_users" TO "postgres";
