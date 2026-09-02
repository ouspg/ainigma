-- The external group used for access to a course definition.
-- One group may intentionally serve several course definitions.
create table private.course_definition_external_groups (
  course_definition_key text primary key,
  provider_kind text not null default 'github',
  provider_issuer text not null default 'github.com',
  external_group_id text not null,
  external_group_handle text not null,
  email_domain_enforced boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  constraint course_definition_external_groups_definition_key_check check (
    course_definition_key ~ '^[a-z][a-z0-9-]{2,63}$'
  ),
  constraint course_definition_external_groups_provider_kind_check check (
    provider_kind = btrim(provider_kind)
    and provider_kind ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  constraint course_definition_external_groups_provider_issuer_check check (
    provider_issuer = btrim(provider_issuer)
    and char_length(provider_issuer) between 1 and 255
    and provider_issuer !~ '[[:space:]]'
  ),
  constraint course_definition_external_groups_group_id_check check (
    external_group_id = btrim(external_group_id)
    and char_length(external_group_id) between 1 and 255
  ),
  constraint course_definition_external_groups_org_slug_check check (
    external_group_handle = btrim(external_group_handle)
    and char_length(external_group_handle) between 1 and 255
  ),
  constraint course_definition_external_groups_repository_target_unique unique (
    course_definition_key, external_group_id, external_group_handle
  )
);

create table private.course_definition_external_email_domains (
  course_definition_key text not null references private.course_definition_external_groups (course_definition_key) on delete cascade,
  domain_suffix text not null,
  primary key (course_definition_key, domain_suffix),
  constraint course_definition_external_email_domains_suffix_check check (
    domain_suffix = lower(btrim(domain_suffix))
    and domain_suffix !~ '[[:space:]@]'
    and domain_suffix !~ '(^[.]|[.]$|[.][.])'
    and domain_suffix ~ '^[a-z0-9-]+([.][a-z0-9-]+)*$'
  )
);

comment on table private.course_definition_external_groups is
  'The trusted external provider group configured for each reusable course definition.';
comment on column private.course_definition_external_groups.provider_kind is
  'Provider adapter key, currently github; it selects the external integration used for invitations and repositories.';
comment on column private.course_definition_external_groups.provider_issuer is
  'Identifier issuer used to select verified profile facts for this provider instance.';
comment on column private.course_definition_external_groups.external_group_id is
  'Stable provider group ID used for external membership verification when configured; the handle is only a display snapshot.';
comment on column private.course_definition_external_groups.external_group_handle is
  'Current provider group handle for diagnostics and display; external_group_id is authoritative.';
comment on column private.course_definition_external_groups.email_domain_enforced is
  'Whether email invitation targets must match the configured domain suffixes.';
comment on table private.course_definition_external_email_domains is
  'Allowed email domain suffixes for invitations to a course definition.';

create index course_definition_external_groups_group_id_idx
  on private.course_definition_external_groups (external_group_id);
