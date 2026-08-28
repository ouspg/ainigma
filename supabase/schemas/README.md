# Supabase schemas

These ordered files are the declarative source of truth for the application database:

- `00_identity_foundation.sql` — profiles, Auth-account links, and verified external identifiers.
- `04_course_definition_github_organizations.sql` — trusted GitHub organization per reusable course definition.
- `05_course_definition_releases.sql` — immutable compiler-built course-definition releases.
- `10_course_offerings.sql` — operational course offerings and their lifecycle fields.
- `20_course_authorization.sql` — memberships, access requests, rosters, GitHub access,
  repository provisioning, RLS, and RPCs.

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

GitHub organization identity is configured for the course definition, while an access request and
GitHub access record belong to one concrete offering and profile. The stable organization ID is
authoritative; the slug is retained for display and diagnostics. Confirmed GitHub access activates
the offering membership but does not create a repository. An authenticated learner may separately
call `request_my_course_repository(offering_key)`; only then does
`course_repository_provisioning` store one durable repository job for that offering/profile.
Trusted workers claim jobs with leases, create or reuse the marked private repository, grant the
user `maintain` permission, and complete or retry the job through private RPCs. The GitHub user ID is
the authoritative identity; the current username is retained only as a provider API handle and
repository-name input. The access row also stores the exact GitHub organization invitation ID, and
acceptance requires that ID plus the user ID to appear in the provider audit trail. Browser clients
cannot read or write these tables directly.

Only published offerings are returned to the GitHub reconciliation worker. Transient provider
failures preserve confirmed access, and three consecutive complete snapshots must omit a member
before the database revokes offering membership. Repository names become immutable when first
claimed, retries use bounded exponential backoff, and permanent or exhausted failures become
`blocked` for operator review.
