set local check_function_bodies = off;

create table "private"."course_definition_github_organizations" (
  "course_definition_key" text                     not null,
  "github_org_id"         bigint                   not null,
  "github_org_slug"       text                     not null,
  "created_at"            timestamp with time zone not null default clock_timestamp(),
  constraint "course_definition_github_organizations_definition_key_check" check ((course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'::text)),
  constraint "course_definition_github_organizations_org_id_check" check ((github_org_id > 0)),
  constraint "course_definition_github_organizations_org_slug_check"
    check (((github_org_slug = btrim(github_org_slug)) AND ((char_length(github_org_slug) >= 1) AND (char_length(github_org_slug) <= 255)))),
  constraint "course_definition_github_organizations_pkey" primary key (course_definition_key)
);

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
  v_expected_github_org_id bigint;
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

  select organization.github_org_id into v_expected_github_org_id
  from public.courses as course
  join private.course_definition_github_organizations as organization
    on organization.course_definition_key = course.course_definition_key
  where course.id = p_course_id;

  if not found or p_github_org_id is distinct from v_expected_github_org_id then
    raise exception using errcode = '42501', message = 'github_organization_mismatch';
  end if;

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

alter table "private"."course_definition_releases"
  add constraint "course_definition_releases_github_organization_fkey" foreign key (course_definition_key)
    references private.course_definition_github_organizations(course_definition_key) on delete restrict;

alter table "public"."courses"
  add constraint "courses_course_definition_github_organization_fkey" foreign key (course_definition_key)
    references private.course_definition_github_organizations(course_definition_key) on delete restrict;

create index course_definition_github_organizations_org_id_idx on private.course_definition_github_organizations using btree (github_org_id);

comment on column "private"."course_definition_github_organizations"."github_org_id" is 'Stable GitHub organization ID used for authorization; the slug is only a display snapshot.';

comment on column "private"."course_definition_github_organizations"."github_org_slug" is 'Current GitHub organization slug for diagnostics and display; github_org_id is authoritative.';

comment on table "private"."course_definition_github_organizations" is 'The trusted GitHub organization configured for each reusable course definition.';

grant select on table "private"."course_definition_github_organizations" to "ainigma_function_owner";

grant delete, insert, maintain, references, select, trigger, truncate, update on table "private"."course_definition_github_organizations" to "postgres";
