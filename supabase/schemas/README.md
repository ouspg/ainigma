# Supabase schemas

These ordered files are the declarative source of truth for the application database:

- `00_identity_foundation.sql` — profiles, Auth-account links, and verified external identifiers.
- `04_course_definition_github_organizations.sql` — trusted GitHub organization per reusable course definition.
- `05_course_definition_releases.sql` — immutable compiler-built course-definition releases.
- `10_course_offerings.sql` — operational course offerings and their lifecycle fields.
- `20_course_authorization.sql` — memberships, access requests, rosters, GitHub access, RLS, and RPCs.

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

GitHub organization identity is configured for the course definition, while an access request and
GitHub access record belong to one concrete offering and profile. The stable organization ID is
authoritative; the slug is retained for display and diagnostics.
