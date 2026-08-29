---
title: Version 1 implementation status
---

Confirmation against `plan.md`

The database matches the plan’s Increment 1 model: identity, courses, memberships, access requests, roster allowlists, GitHub access state, private helpers, forced RLS, deny-by-default grants, seed fixtures, and pgTAP tests are present.

Relevant implementation: [`schemas/00_identity_foundation.sql`](/Users/nicce/teaching/ainigma/supabase/schemas/00_identity_foundation.sql:1) and the ordered course schemas documented in [`schemas/README.md`](/Users/nicce/teaching/ainigma/supabase/schemas/README.md:1).

Remaining plan gaps:

- GitHub OAuth is not configured yet; the `[auth.external.github]` section is absent. Global signup is still enabled, although email/phone signup and anonymous sign-in are disabled.
- The anonymous published-offering catalog is implemented by `list_available_courses()`; course access and all learner state remain authenticated.
- Tasks, runtime, publication, grading, queues, and worker infrastructure belong to later increments and are not implemented.
- Hosted Supavisor and real-JWT integration checks from the plan remain unverified.

## PostgREST application endpoints

The API exposes `public` and `graphql_public` schemas, but `graphql_public` currently has no application objects.

### Course discovery RPC endpoint

Published offering metadata is available through:

- `GET /rest/v1/rpc/list_available_courses`

This endpoint returns only offerings whose database status is `published`. It does not grant access or expose memberships. A learner still calls `request_course_access` for the selected `offering_key`.

The RPC has `EXECUTE` for `anon` and `authenticated`; direct table reads remain denied. The
function is read-only and `STABLE`, so GET is appropriate and can be cached. Client libraries
that default RPC calls to POST must explicitly request the GET form.

### Authenticated RPC endpoints

All have `EXECUTE` for `authenticated` and none for `anon`:

- `POST /rest/v1/rpc/get_my_profile`
- `POST /rest/v1/rpc/update_my_profile`
- `POST /rest/v1/rpc/list_my_courses`
- `POST /rest/v1/rpc/list_course_roster`
- `POST /rest/v1/rpc/request_course_access`
- `POST /rest/v1/rpc/list_my_course_access_requests`
- `POST /rest/v1/rpc/list_course_access_requests`
- `POST /rest/v1/rpc/approve_course_access_requests`
- `POST /rest/v1/rpc/reject_course_access_requests`

The RPCs derive identity from `auth.uid()` and enforce ownership/course-role checks internally.

### Table routes

These public tables exist:

- `/rest/v1/profiles`
- `/rest/v1/courses`
- `/rest/v1/course_memberships`

However, `anon` and `authenticated` have no table privileges for any operation. RLS is enabled and forced on all three. Therefore direct table reads and writes are blocked; access is through the RPCs only.

Private tables, views, and helper functions are not PostgREST endpoints because `private` is not an exposed schema and browser roles lack its schema usage. This follows Supabase’s grant-plus-RLS model: grants determine whether an object is reachable, while RLS limits rows afterward. [Supabase API security](https://supabase.com/docs/guides/api/securing-your-api)

## Can `supabase/migrations/` be deleted?

No—not safely as a folder.

Declarative schemas are the source of truth, but migrations remain the generated deployment/reset history. Deleting them would make `db reset` unable to recreate the database and would break migration-based deployment. Supabase’s declarative workflow still generates and versions migrations. [Declarative database schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas)

If this database has never been deployed remotely, the old migrations can be squashed into one initial generated migration, but the `migrations/` directory should remain. I would not delete them without first confirming there is no remote migration history.
