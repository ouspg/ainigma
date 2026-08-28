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
  "requested_role"       text                     not null default 'learner'::text,
  "reason"               text,
  "status"               text                     not null default 'pending'::text,
  "decision_source"      text                     not null default 'owner'::text,
  "requested_at"         timestamp with time zone not null default clock_timestamp(),
  "decided_at"           timestamp with time zone,
  "decided_by"           uuid,
  "decision_reason"      text,
  constraint "course_access_requests_decision_shape_check"
    check ((((status = ANY (ARRAY['pending'::text, 'cancelled'::text])) AND (decided_at IS NULL) AND (decided_by IS NULL)) OR ((status = 'approved'::text) AND (decided_at IS
    NOT NULL) AND ((decided_by IS NOT NULL) OR (decision_source = 'allowlist'::text))) OR ((status = 'rejected'::text) AND (decided_at IS NOT NULL) AND (decided_by IS
    NOT NULL) AND (decision_source = 'owner'::text)))),
  constraint "course_access_requests_decision_source_check" check ((decision_source = ANY (ARRAY['owner'::text, 'allowlist'::text]))),
  constraint "course_access_requests_pkey" primary key (id),
  constraint "course_access_requests_reason_check" check (((reason IS NULL) OR ((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000))))),
  constraint "course_access_requests_role_check" check ((requested_role = 'learner'::text)),
  constraint "course_access_requests_status_check" check ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);

alter table "private"."course_access_requests"
  enable row level security;

alter table "private"."course_access_requests"
  force row level security;

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
  "previous_role"    text,
  "previous_status"  text,
  "new_role"         text                     not null,
  "new_status"       text                     not null,
  "actor_profile_id" uuid,
  "reason"           text                     not null,
  "created_at"       timestamp with time zone not null default clock_timestamp(),
  constraint "course_membership_events_kind_check" check ((event_kind = ANY (ARRAY['created'::text, 'transitioned'::text]))),
  constraint "course_membership_events_new_role_check" check ((new_role = ANY (ARRAY['owner'::text, 'instructor'::text, 'learner'::text]))),
  constraint "course_membership_events_new_status_check" check ((new_status = ANY (ARRAY['active'::text, 'suspended'::text, 'revoked'::text]))),
  constraint "course_membership_events_pkey" primary key (id),
  constraint "course_membership_events_previous_role_check" check (((previous_role IS NULL) OR (previous_role = ANY (ARRAY['owner'::text, 'instructor'::text, 'learner'::text])))),
  constraint "course_membership_events_previous_status_check"
    check (((previous_status IS NULL) OR (previous_status = ANY (ARRAY['active'::text, 'suspended'::text, 'revoked'::text])))),
  constraint "course_membership_events_reason_check" check (((reason = btrim(reason)) AND ((char_length(reason) >= 1) AND (char_length(reason) <= 2000)))),
  constraint "course_membership_events_shape_check"
    check ((((event_kind = 'created'::text) AND (previous_role IS NULL) AND (previous_status IS NULL)) OR ((event_kind = 'transitioned'::text) AND (previous_role IS
    NOT NULL) AND (previous_status IS NOT NULL))))
);

create table "private"."course_roster_allowlist" (
  "id"                          uuid                     not null default gen_random_uuid(),
  "course_id"                   uuid                     not null,
  "identifier_kind"             text                     not null,
  "identifier_issuer"           text                     not null,
  "identifier_scheme_version"   integer                  not null,
  "normalized_identifier_value" text                     not null,
  "role"                        text                     not null default 'learner'::text,
  "source"                      text                     not null,
  "status"                      text                     not null default 'active'::text,
  "imported_at"                 timestamp with time zone not null default clock_timestamp(),
  "imported_by"                 uuid,
  "revoked_at"                  timestamp with time zone,
  constraint "course_roster_allowlist_issuer_check"
    check (((identifier_issuer = btrim(identifier_issuer)) AND ((char_length(identifier_issuer) >= 1) AND (char_length(identifier_issuer) <= 255)))),
  constraint "course_roster_allowlist_kind_check" check ((identifier_kind = ANY (ARRAY['email'::text, 'github_user_id'::text, 'student_identifier'::text]))),
  constraint "course_roster_allowlist_pkey" primary key (id),
  constraint "course_roster_allowlist_revoked_shape_check" check ((((status = 'active'::text) AND (revoked_at IS NULL)) OR ((status = 'revoked'::text) AND (revoked_at IS
    NOT NULL)))),
  constraint "course_roster_allowlist_role_check" check ((role = 'learner'::text)),
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

create table "private"."github_course_access" (
  "course_id"         uuid                     not null,
  "profile_id"        uuid                     not null,
  "access_request_id" uuid                     not null,
  "github_org_id"     bigint,
  "github_org_slug"   text,
  "github_user_id"    text                     not null,
  "state"             text                     not null default 'not_started'::text,
  "invited_at"        timestamp with time zone,
  "accepted_at"       timestamp with time zone,
  "last_checked_at"   timestamp with time zone,
  "failure_code"      text,
  constraint "github_course_access_failure_check"
    check (((failure_code IS NULL) OR ((failure_code = btrim(failure_code)) AND ((char_length(failure_code) >= 1) AND (char_length(failure_code) <= 255))))),
  constraint "github_course_access_org_shape_check"
    check ((((state = 'not_started'::text) AND (github_org_id IS NULL) AND (github_org_slug IS NULL)) OR ((state <> 'not_started'::text) AND (github_org_id IS
    NOT NULL) AND (github_org_slug IS NOT NULL)))),
  constraint "github_course_access_org_slug_check"
    check (((github_org_slug IS NULL) OR ((github_org_slug = btrim(github_org_slug)) AND ((char_length(github_org_slug) >= 1) AND (char_length(github_org_slug) <= 255))))),
  constraint "github_course_access_pkey" primary key (course_id, profile_id),
  constraint "github_course_access_state_check"
    check ((state = ANY (ARRAY['not_started'::text, 'invitation_pending'::text, 'sso_required'::text, 'active'::text, 'failed'::text, 'revoked'::text]))),
  constraint "github_course_access_user_id_check" check (((github_user_id = btrim(github_user_id)) AND (github_user_id ~ '^[0-9]+$'::text)))
);

alter table "private"."github_course_access"
  enable row level security;

alter table "private"."github_course_access"
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
  constraint "profile_identifiers_kind_check" check ((kind = ANY (ARRAY['email'::text, 'github_user_id'::text, 'github_username'::text, 'student_identifier'::text]))),
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
  "role"                           text                     not null,
  "status"                         text                     not null default 'active'::text,
  "created_at"                     timestamp with time zone not null default clock_timestamp(),
  "suspended_at"                   timestamp with time zone,
  "revoked_at"                     timestamp with time zone,
  "created_from_access_request_id" uuid,
  constraint "course_memberships_owner_status_check" check (((role <> 'owner'::text) OR (status = 'active'::text))),
  constraint "course_memberships_pkey" primary key (course_id, profile_id),
  constraint "course_memberships_role_check" check ((role = ANY (ARRAY['owner'::text, 'instructor'::text, 'learner'::text]))),
  constraint "course_memberships_status_check" check ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'revoked'::text]))),
  constraint "course_memberships_status_timestamps_check"
    check ((((status = 'active'::text) AND (suspended_at IS NULL) AND (revoked_at IS NULL)) OR ((status = 'suspended'::text) AND (suspended_at IS
    NOT NULL) AND (revoked_at IS NULL)) OR ((status = 'revoked'::text) AND (revoked_at IS NOT NULL))))
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
  "status"                       text                     not null default 'draft'::text,
  "starts_at"                    timestamp with time zone,
  "ends_at"                      timestamp with time zone,
  "external_url"                 text,
  "created_at"                   timestamp with time zone not null default clock_timestamp(),
  "updated_at"                   timestamp with time zone not null default clock_timestamp(),
  "enrollment_mode"              text                     not null default 'approval_required'::text,
  constraint "courses_code_check" check (((code = btrim(code)) AND ((char_length(code) >= 1) AND (char_length(code) <= 32)))),
  constraint "courses_course_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "courses_enrollment_mode_check" check ((enrollment_mode = ANY (ARRAY['approval_required'::text, 'allowlist_auto'::text, 'closed'::text]))),
  constraint "courses_external_url_check" check (((external_url IS NULL) OR ((char_length(external_url) <= 2048) AND (external_url ~ '^https?://'::text)))),
  constraint "courses_offering_key_check" check ((offering_key ~ '^[a-z][a-z0-9-]{2,127}$'::text)),
  constraint "courses_offering_key_key" unique (offering_key),
  constraint "courses_pkey" primary key (id),
  constraint "courses_status_check" check ((status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text]))),
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

create or replace function private.add_course_membership (
  p_course_id        uuid,
  p_profile_id       uuid,
  p_role             text,
  p_actor_profile_id uuid,
  p_reason           text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_actor_role text;
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

alter function "private"."add_course_membership"(uuid, uuid, text, uuid, text) owner to "ainigma_function_owner";

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

create or replace function private.confirm_github_course_access (
  p_course_id       uuid,
  p_profile_id      uuid,
  p_github_org_id   bigint,
  p_github_org_slug text,
  p_github_user_id  text
)
  returns void
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_access private.github_course_access%rowtype;
  v_request private.course_access_requests%rowtype;
begin
  select access_row.* into v_access
  from private.github_course_access as access_row
  where access_row.course_id = p_course_id and access_row.profile_id = p_profile_id
  for update;

  if not found then raise exception using errcode = '23503', message = 'github_access_not_started'; end if;

  select request_row.* into v_request
  from private.course_access_requests as request_row
  where request_row.id = v_access.access_request_id and request_row.status = 'approved';
  if not found then raise exception using errcode = '42501', message = 'course_access_not_approved'; end if;

  if not exists (
    select 1 from private.profile_identifiers as identifier
    where identifier.profile_id = p_profile_id
      and identifier.kind = 'github_user_id'
      and identifier.issuer = 'github.com'
      and identifier.normalized_value = p_github_user_id
      and identifier.revoked_at is null
  ) then
    raise exception using errcode = '42501', message = 'github_identity_mismatch';
  end if;

  update private.github_course_access
  set github_org_id = p_github_org_id,
      github_org_slug = p_github_org_slug,
      github_user_id = p_github_user_id,
      state = 'active',
      accepted_at = coalesce(accepted_at, clock_timestamp()),
      last_checked_at = clock_timestamp(),
      failure_code = null
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
    'GitHub course organization membership confirmed'
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

alter function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, text) owner to "ainigma_function_owner";

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
  p_roles     text[]
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

alter function "private"."has_course_role"(uuid, text[]) owner to "ainigma_function_owner";

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
  AS $function$
  select
    'orphan_profile'::text,
    profile.id,
    null::uuid,
    null::uuid,
    'profile has no Auth user link'::text
  from public.profiles as profile
  where not exists (
    select 1
    from private.auth_user_links as link
    where link.profile_id = profile.id
  )

  union all

  select
    'unlinked_auth_identity'::text,
    null::uuid,
    identity_row.user_id,
    identity_row.id,
    'Auth identity user has no application profile link'::text
  from private.auth_identities as identity_row
  where not exists (
    select 1
    from private.auth_user_links as link
    where link.auth_user_id = identity_row.user_id
  );
$function$;

alter function "private"."report_identity_anomalies"() owner to "ainigma_function_owner";

create or replace function private.request_auth_user_id()
  returns uuid
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select auth.uid();
$function$;

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
    'github_user_id',
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
      and kind = 'github_username'
      and issuer = 'github.com'
      and scheme_version = 1
      and normalized_value <> v_username
      and revoked_at is null;

    perform private.upsert_verified_identifier(
      v_profile_id,
      'github_username',
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
  p_new_role         text,
  p_new_status       text,
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
  v_actor_role text;
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

alter function "private"."transition_course_membership"(uuid, uuid, text, text, uuid, text) owner to "ainigma_function_owner";

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
begin
  select course.id into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key;
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
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
          and identifier.kind = 'github_user_id'
          and identifier.issuer = 'github.com'
          and identifier.revoked_at is null
      )
  ) then
    raise sqlstate 'PT403' using message = 'github_identity_not_provisioned';
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
  insert into private.github_course_access (course_id, profile_id, access_request_id, github_user_id, state)
  select changed.course_id, changed.requester_profile_id, changed.id, identifier.normalized_value, 'not_started'
  from changed
  join private.profile_identifiers as identifier
    on identifier.profile_id = changed.requester_profile_id
   and identifier.kind = 'github_user_id'
   and identifier.issuer = 'github.com'
   and identifier.revoked_at is null
  on conflict (course_id, profile_id) do update set access_request_id = excluded.access_request_id;

  get diagnostics v_count = row_count;
  return v_count;
end
$function$;

alter function "public"."approve_course_access_requests"(text, uuid[]) owner to "ainigma_function_owner";

create or replace function public.get_my_profile()
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return query
  select profile.display_name, profile.created_at, profile.updated_at
  from public.profiles as profile
  where profile.id = v_profile_id;
end
$function$;

alter function "public"."get_my_profile"() owner to "ainigma_function_owner";

create or replace function public.list_course_access_requests (
  p_offering_key         text,
  p_status               text default 'pending'::text,
  p_authorization_filter text default null::text
)
  returns table (
    request_id           uuid,
    offering_key         text,
    display_name         text,
    github_username      text,
    verified_email       text,
    reason               text,
    status               text,
    authorization_status text,
    requested_at         timestamp with time zone,
    decided_at           timestamp with time zone,
    github_access_state  text
  )
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
  v_course_id uuid;
begin
  select course.id into v_course_id
  from public.courses as course
  where course.offering_key = p_offering_key;

  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
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
        and identifier.kind = 'github_username'
        and identifier.issuer = 'github.com'
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
    access_row.state
  from private.course_access_requests as request_row
  join public.courses as course on course.id = request_row.course_id
  join public.profiles as profile on profile.id = request_row.requester_profile_id
  left join private.github_course_access as access_row on access_row.access_request_id = request_row.id
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

alter function "public"."list_course_access_requests"(text, text, text) owner to "ainigma_function_owner";

create or replace function public.list_course_roster (
  p_offering_key text
)
  returns table (
    display_name text,
    role         text,
    status       text,
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

  -- Use one response for missing and unauthorized courses to avoid revealing
  -- whether an offering exists through the RPC.
  if v_course_id is null
    or not private.has_course_role(v_course_id, array['owner', 'instructor']::text[])
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
    offering_key        text,
    request_id          uuid,
    status              text,
    reason              text,
    requested_at        timestamp with time zone,
    decided_at          timestamp with time zone,
    github_access_state text
  )
  language sql
  stable
  security definer
  set search_path to ''
  AS $function$
  select
    course.offering_key,
    request_row.id,
    request_row.status,
    request_row.reason,
    request_row.requested_at,
    request_row.decided_at,
    access_row.state
  from private.course_access_requests as request_row
  join public.courses as course on course.id = request_row.course_id
  left join private.github_course_access as access_row
    on access_row.access_request_id = request_row.id
  where request_row.requester_profile_id = private.current_profile_id()
  order by request_row.requested_at desc;
$function$;

alter function "public"."list_my_course_access_requests"() owner to "ainigma_function_owner";

create or replace function public.list_my_courses()
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return jsonb_build_object(
    'courses', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'offering_key', course.offering_key,
            'course_definition_key', course.course_definition_key,
            'course_definition_release_id', course.course_definition_release_id,
            'code', course.code,
            'course_status', course.status,
            'membership_role', membership.role,
            'membership_status', membership.status,
            'starts_at', course.starts_at,
            'ends_at', course.ends_at,
            'external_url', course.external_url,
            'created_at', course.created_at,
            'updated_at', course.updated_at
          )
          order by course.offering_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and membership.status = 'active'
          and (
            course.status in ('published', 'archived')
            or (
              course.status = 'draft'
              and membership.role in ('owner', 'instructor')
            )
          )
      ),
      '[]'::jsonb
    ),
    'inactive_memberships', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'offering_key', course.offering_key,
            'course_definition_release_id', course.course_definition_release_id,
            'course_status', course.status,
            'membership_role', membership.role,
            'membership_status', membership.status,
            'created_at', membership.created_at,
            'suspended_at', membership.suspended_at,
            'revoked_at', membership.revoked_at
          )
          order by course.offering_key
        )
        from public.courses as course
        join public.course_memberships as membership
          on membership.course_id = course.id
        where membership.profile_id = v_profile_id
          and not (
            membership.status = 'active'
            and (
              course.status in ('published', 'archived')
              or (
                course.status = 'draft'
                and membership.role in ('owner', 'instructor')
              )
            )
          )
      ),
      '[]'::jsonb
    )
  );
end
$function$;

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
  if v_course_id is null or not private.has_course_role(v_course_id, array['owner']::text[]) then
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
  v_auto_approved boolean;
  v_request private.course_access_requests%rowtype;
  v_membership public.course_memberships%rowtype;
begin
  if p_reason is not null and (p_reason <> btrim(p_reason) or char_length(p_reason) not between 1 and 2000) then
    raise sqlstate 'PT400' using message = 'invalid_request_reason';
  end if;

  select course.id, course.enrollment_mode
  into v_course_id, v_enrollment_mode
  from public.courses as course
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
      'state', case when v_request.status = 'approved' then 'awaiting_github_access' else 'pending' end,
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
        and identifier.kind = 'github_user_id'
        and identifier.issuer = 'github.com'
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
    case when v_auto_approved then 'approved' else 'pending' end,
    case when v_auto_approved then 'allowlist' else 'owner' end,
    case when v_auto_approved then clock_timestamp() else null end
  )
  returning * into v_request;

  if v_auto_approved then
    insert into private.github_course_access (
      course_id, profile_id, access_request_id, github_user_id, state
    )
    select
      v_course_id,
      v_profile_id,
      v_request.id,
      identifier.normalized_value,
      'not_started'
    from private.profile_identifiers as identifier
    where identifier.profile_id = v_profile_id
      and identifier.kind = 'github_user_id'
      and identifier.issuer = 'github.com'
      and identifier.revoked_at is null
    order by identifier.last_verified_at desc
    limit 1;

    return jsonb_build_object(
      'state', 'awaiting_github_access',
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

create or replace function public.update_my_profile (
  p_display_name text
)
  returns table (
    display_name text,
    created_at   timestamp with time zone,
    updated_at   timestamp with time zone
  )
  language plpgsql
  security definer
  set search_path to ''
  AS $function$
declare
  v_profile_id uuid := private.current_profile_id();
begin
  return query
  update public.profiles as profile
  set display_name = p_display_name
  where profile.id = v_profile_id
  returning profile.display_name, profile.created_at, profile.updated_at;
end
$function$;

alter function "public"."update_my_profile"(text) owner to "ainigma_function_owner";

alter table "private"."auth_user_links"
  add constraint "auth_user_links_auth_user_id_fkey" foreign key (auth_user_id) references auth.users(id) on delete cascade;

alter table "private"."github_course_access"
  add constraint "github_course_access_access_request_id_fkey" foreign key (access_request_id) references private.course_access_requests(id) on delete restrict;

alter table "private"."profile_identifiers"
  add constraint "profile_identifiers_source_auth_user_id_fkey" foreign key (source_auth_user_id) references auth.users(id) on delete set null;

alter table "public"."course_memberships"
  add constraint "course_memberships_access_request_fk" foreign key (created_from_access_request_id) references private.course_access_requests(id) on delete restrict;

alter table "public"."courses"
  add constraint "courses_course_definition_release_fkey" foreign key (course_definition_release_id, course_definition_key)
    references private.course_definition_releases(id, course_definition_key) on delete restrict;

alter table "private"."course_access_requests"
  add constraint "course_access_requests_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."course_membership_events"
  add constraint "course_membership_events_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."course_roster_allowlist"
  add constraint "course_roster_allowlist_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

alter table "private"."github_course_access"
  add constraint "github_course_access_course_id_fkey" foreign key (course_id) references public.courses(id) on delete restrict;

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

alter table "private"."github_course_access"
  add constraint "github_course_access_profile_id_fkey" foreign key (profile_id) references public.profiles(id) on delete restrict;

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

create view "private"."auth_users" AS  SELECT id,
    created_at,
    deleted_at
   FROM auth.users auth_user;

create index auth_user_links_profile_id_idx on private.auth_user_links using btree (profile_id);

create index course_access_requests_course_status_idx on private.course_access_requests using btree (course_id, status, requested_at);

create unique index course_access_requests_pending_uidx on private.course_access_requests using btree (course_id, requester_profile_id)
  where (status = 'pending'::text);

create index course_definition_releases_latest_idx on private.course_definition_releases using btree (course_definition_key, created_at desc, id);

create index course_membership_events_course_created_idx on private.course_membership_events using btree (course_id, created_at desc);

create index course_membership_events_profile_created_idx on private.course_membership_events using btree (profile_id, created_at desc);

create unique index course_roster_allowlist_active_uidx on private.course_roster_allowlist
  using btree (course_id, identifier_kind, identifier_issuer, identifier_scheme_version, normalized_identifier_value)
  where (status = 'active'::text);

create index course_roster_allowlist_course_idx on private.course_roster_allowlist using btree (course_id, status);

create unique index github_course_access_request_uidx on private.github_course_access using btree (access_request_id);

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
  where ((role = 'owner'::text) AND (status = 'active'::text));

create index course_memberships_profile_status_role_idx on public.course_memberships using btree (profile_id, status, role, course_id);

create index courses_course_definition_key_idx on public.courses using btree (course_definition_key);

create index courses_course_definition_release_id_idx on public.courses using btree (course_definition_release_id);

create index courses_status_window_idx on public.courses using btree (status, starts_at, ends_at);

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

create policy "course_roster_allowlist_function_access" on "private"."course_roster_allowlist"
  for all
  to "ainigma_function_owner", "ainigma_maintenance"
  using (true)
  with check (true);

create policy "github_course_access_function_access" on "private"."github_course_access"
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
    (((profile_id = ( select private.current_profile_id() as current_profile_id)) or ( select private.has_course_role(course_memberships.course_id, ARRAY['owner'::text,
    'instructor'::text]) as has_course_role)));

create policy "courses_function_owner_access" on "public"."courses"
  for all
  to "ainigma_function_owner"
  using (true)
  with check (true);

create policy "courses_select_enrolled" on "public"."courses"
  for select
  to "authenticated"
  using
    ((((status = 'published'::text) AND ( select private.has_course_role(courses.id, ARRAY['owner'::text, 'instructor'::text, 'learner'::text]) as has_course_role)) or ((status =
    'draft'::text) AND ( select private.has_course_role(courses.id, ARRAY['owner'::text, 'instructor'::text]) as has_course_role))));

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

comment on column "private"."course_definition_releases"."artifact_ref" is 'Immutable deployable artifact reference resolved by the compiler and deployment system.';

comment on column "public"."courses"."course_definition_key" is 'Immutable key of the reusable Git-authored course definition rendered for this offering.';

comment on column "public"."courses"."course_definition_release_id" is 'Exact compiler release currently rendered for this offering; ended offerings stop advancing.';

comment on column "public"."courses"."offering_key" is 'Globally unique immutable key for one term, cohort, or operational course space.';

comment on table "private"."course_definition_releases" is 'Immutable Ainigma compiler outputs for reusable course definitions.';

comment on table "public"."courses" is 'Operational course offerings. Titles, navigation, and authored content remain in Git.';

comment on table "public"."profiles" is 'Provider-neutral application identities. Authorization claims remain private.';

revoke all on function "private"."add_course_membership"(uuid, uuid, text, uuid, text) from public;

grant execute on function "private"."add_course_membership"(uuid, uuid, text, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."advance_open_course_offerings_to_release"(uuid) from public;

grant execute on function "private"."advance_open_course_offerings_to_release"(uuid) to "ainigma_maintenance";

revoke all on function "private"."branch_course_offering"(text, uuid, text, uuid, timestamp with time zone, timestamp with time zone, text) from public;

grant execute on function "private"."branch_course_offering"(text, uuid, text, uuid, timestamp with time zone, timestamp with time zone, text) to "ainigma_maintenance";

revoke all on function "private"."can_view_profile"(uuid) from public;

grant execute on function "private"."can_view_profile"(uuid) to "authenticated";

revoke all on function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, text) from public;

grant execute on function "private"."confirm_github_course_access"(uuid, uuid, bigint, text, text) to "ainigma_maintenance";

revoke all on function "private"."current_profile_id"() from public;

grant execute on function "private"."current_profile_id"() to "authenticated";

revoke all on function "private"."ensure_auth_user_profile"(uuid) from public;

grant execute on function "private"."ensure_auth_user_profile"(uuid) to "ainigma_maintenance";

revoke all on function "private"."handle_auth_user_created"() from public;

revoke all on function "private"."has_course_role"(uuid, text[]) from public;

grant execute on function "private"."has_course_role"(uuid, text[]) to "authenticated";

revoke all on function "private"."reconcile_auth_identities"() from public;

grant execute on function "private"."reconcile_auth_identities"() to "ainigma_maintenance";

revoke all on function "private"."reconcile_auth_users"() from public;

grant execute on function "private"."reconcile_auth_users"() to "ainigma_maintenance";

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

revoke all on function "private"."transition_course_membership"(uuid, uuid, text, text, uuid, text) from public;

grant execute on function "private"."transition_course_membership"(uuid, uuid, text, text, uuid, text) to "ainigma_maintenance";

revoke all on function "private"."upsert_verified_identifier"(uuid, text, text, integer, text, timestamp with time zone, uuid, text) from public;

revoke all on function "public"."approve_course_access_requests"(text, uuid[]) from public;

revoke all on function "public"."approve_course_access_requests"(text, uuid[]) from "ainigma_function_owner";

grant execute on function "public"."approve_course_access_requests"(text, uuid[]) to "ainigma_function_owner";

grant execute on function "public"."approve_course_access_requests"(text, uuid[]) to "authenticated";

revoke all on function "public"."get_my_profile"() from public;

revoke all on function "public"."get_my_profile"() from "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "ainigma_function_owner";

grant execute on function "public"."get_my_profile"() to "authenticated";

revoke all on function "public"."list_course_access_requests"(text, text, text) from public;

revoke all on function "public"."list_course_access_requests"(text, text, text) from "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, text, text) to "ainigma_function_owner";

grant execute on function "public"."list_course_access_requests"(text, text, text) to "authenticated";

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

grant insert, select on table "private"."course_definition_releases" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_releases" to "postgres";

grant insert, select on table "private"."course_membership_events" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_membership_events" to "postgres";

grant insert, select, update on table "private"."course_roster_allowlist" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_roster_allowlist" to "postgres";

grant insert, select, update on table "private"."github_course_access" to "ainigma_function_owner", "ainigma_maintenance";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."github_course_access" to "postgres";

grant insert, select, update on table "private"."profile_identifiers" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."profile_identifiers" to "postgres";

grant insert, select, update on table "public"."course_memberships" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."course_memberships" to "postgres";

grant insert, select, update on table "public"."courses" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."courses" to "postgres";

grant insert, select, update on table "public"."profiles" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "public"."profiles" to "postgres";

grant select on table "private"."auth_identities" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."auth_identities" to "postgres";

grant select on table "private"."auth_users" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."auth_users" to "postgres";
