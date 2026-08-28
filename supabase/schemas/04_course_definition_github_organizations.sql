-- The GitHub organization used for access to a course definition.
-- One organization may intentionally serve several course definitions.
create table private.course_definition_github_organizations (
  course_definition_key text primary key,
  github_org_id bigint not null,
  github_org_slug text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint course_definition_github_organizations_definition_key_check check (
    course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'
  ),
  constraint course_definition_github_organizations_org_id_check check (
    github_org_id > 0
  ),
  constraint course_definition_github_organizations_org_slug_check check (
    github_org_slug = btrim(github_org_slug)
    and char_length(github_org_slug) between 1 and 255
  )
);

comment on table private.course_definition_github_organizations is
  'The trusted GitHub organization configured for each reusable course definition.';
comment on column private.course_definition_github_organizations.github_org_id is
  'Stable GitHub organization ID used for authorization; the slug is only a display snapshot.';
comment on column private.course_definition_github_organizations.github_org_slug is
  'Current GitHub organization slug for diagnostics and display; github_org_id is authoritative.';

create index course_definition_github_organizations_org_id_idx
  on private.course_definition_github_organizations (github_org_id);
