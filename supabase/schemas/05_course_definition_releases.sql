-- Immutable compiler output built from the single living directory for a course definition.
create table private.course_definition_releases (
  id uuid primary key default gen_random_uuid(),
  course_definition_key text not null,
  source_commit_sha text not null,
  course_release_digest text not null,
  artifact_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint course_definition_releases_definition_key_check check (
    course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'
  ),
  constraint course_definition_releases_github_organization_fkey foreign key (
    course_definition_key
  ) references private.course_definition_github_organizations (course_definition_key) on delete restrict,
  constraint course_definition_releases_source_commit_sha_check check (
    source_commit_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'
  ),
  constraint course_definition_releases_digest_check check (
    course_release_digest ~ '^[0-9a-f]{64}$'
  ),
  constraint course_definition_releases_artifact_ref_check check (
    artifact_ref = btrim(artifact_ref)
    and char_length(artifact_ref) between 1 and 2048
  ),
  constraint course_definition_releases_id_definition_key_unique
    unique (id, course_definition_key),
  constraint course_definition_releases_definition_digest_unique
    unique (course_definition_key, course_release_digest)
);

comment on table private.course_definition_releases is
  'Immutable Ainigma compiler outputs for reusable course definitions.';
comment on column private.course_definition_releases.artifact_ref is
  'Immutable deployable artifact reference resolved by the compiler and deployment system.';

create index course_definition_releases_latest_idx
  on private.course_definition_releases (course_definition_key, created_at desc, id);
