# Supabase schemas

These ordered files are the declarative source of truth for the application database:

- `00_identity_foundation.sql` — profiles, Auth-account links, and verified external identifiers.
- `04_course_definition_external_groups.sql` — trusted external provider group per reusable course definition.
- `05_course_definition_releases.sql` — immutable compiler-built course-definition releases.
- `10_course_offerings.sql` — operational course offerings and their lifecycle fields.
- `20_course_memberships.sql` — offering memberships, immutable audit events, and membership operations.
- `21_course_access_requests.sql` — learner access requests and trusted roster allowlists.
- `22_external_course_access.sql` — provider invitations, membership reconciliation, and access activation.
- `23_course_repository_provisioning.sql` — durable, explicitly requested repository jobs.
- `24_course_offering_operations.sql` — compiler-controlled release and offering lifecycle operations.
- `25_course_member_api.sql` — published-course discovery plus authenticated course, roster, access, and repository self-service RPCs.
- `26_course_staff_api.sql` — authenticated access-request administration RPCs.
- `99_application_permissions.sql` — final ownership, grants, RLS policies, and table restrictions.

`roles.sql` and the first schema file enable `plpgsql.extra_errors = 'all'`. This makes ambiguous
names, mismatched strict assignments, and similar compiler-detectable PL/pgSQL hazards fail both
migration sessions and declarative schema loading.

Pure query and update functions use `LANGUAGE SQL` with parsed `BEGIN ATOMIC` bodies. PL/pgSQL is
reserved for triggers, ordered validation, row locking, domain errors, audit sequencing, bounded
retries, and per-row exception isolation. The nullable authorization predicates also remain
PL/pgSQL because their early returns must avoid resolving an authenticated profile. Expressing that
branch with `CASE` in `BEGIN ATOMIC` currently triggers a known
[Supabase CLI migration-parser limitation](https://github.com/supabase/cli/issues/3474).

Course identity has four deliberately separate forms:

- `courses.id` is the internal UUID used by foreign keys.
- `courses.offering_key` identifies one term, cohort, or operational course space.
- `courses.course_definition_key` identifies the reusable Git/MDX course definition rendered for
  that offering.
- `courses.course_definition_release_id` identifies the exact compiler output currently used by
  that offering.

Multiple offerings may share one `course_definition_key`; their memberships and operational state
remain separate. The Ainigma compiler registers immutable definition releases, advances only
non-archived offerings, and branches a new offering from an explicitly selected release. Edit these
schema files first, then follow the declarative migration workflow in the parent `README.md`.

## Rust database types

The Rust worker uses SQLx query macros. The SQLx metadata in the repository's `.sqlx/` directory is
generated from the local database after the declarative schemas have been applied; it is generated
output, not a second schema. Use `npm run supabase:reset` first, then set
`DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres` and run
`npm run sqlx:prepare`. Do not edit `.sqlx/` by hand. `npm run sqlx:check` verifies that the checked
queries and metadata still agree.

External provider group identity is configured for the course definition, while an access request and
external access record belong to one concrete offering and profile. The stable group ID is
authoritative; the slug is retained for display and diagnostics. Confirmed external-provider access activates
the offering membership but does not create a repository. An authenticated learner may separately
call `request_my_course_repository(offering_key)`; only then does
`course_repository_provisioning` store one durable repository job for that offering/profile.
Trusted workers claim jobs with leases, create a private repository from the configured public
repository template (or reuse the marked repository), grant the user `maintain` permission, and
complete or retry the job through private RPCs. The template owner and name are snapshotted on the
job, so the source may differ from the access group and queued jobs remain deterministic. The
provider user ID is the authoritative identity; the current username is retained only as a provider API handle and
repository-name input. The access row also stores the exact provider invitation ID. Email invitations
may bind the provider user ID only after that invitation is accepted; user-ID invitations still require
the pre-linked identity. Browser clients
cannot read or write these tables directly.

Offerings may set `membership_verification` to `approval_only` when first-party SSO or a trusted
allowlist is the access authority. The learner must still create an access request, and owner
approval or allowlist auto-approval creates the local membership without an external invitation or
membership snapshot. The configured provider group remains available as the repository target; a
repository job still requires a verified identity for that provider.

Only published offerings are returned to the external-provider reconciliation worker. Transient provider
failures preserve confirmed access, and three consecutive complete snapshots must omit a member
before the database revokes offering membership. Repository names become immutable when first
claimed, retries use bounded exponential backoff, and permanent or exhausted failures become
`blocked` for operator review.

The `public.list_available_courses()` RPC is the learner discovery endpoint. It returns metadata
for published offerings only, including the `offering_key` needed by
`public.request_course_access()`. It grants no membership and does not expose direct table access;
the small published catalog is also safe for signed-out course discovery.
