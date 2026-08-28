# Local Supabase

The concise schema map and course-identity glossary live in [`schemas/README.md`](schemas/README.md).

From the repository root:

```sh
./node_modules/.bin/supabase --version
./node_modules/.bin/supabase start
./node_modules/.bin/supabase db reset --local --yes
./node_modules/.bin/supabase test db --local
./node_modules/.bin/supabase migration list --local
npm run supabase:types
```

Stop it with `./node_modules/.bin/supabase stop`.

## Local GitHub authentication

Create a GitHub OAuth App for local development with:

```text
Homepage URL:               http://localhost:4323
Authorization callback URL: http://localhost:54321/auth/v1/callback
```

Copy the GitHub OAuth credentials from the repository-level `.env.example` into the ignored root
`.env` file:

```sh
SUPABASE_AUTH_EXTERNAL_GITHUB_CLIENT_ID=...
SUPABASE_AUTH_EXTERNAL_GITHUB_SECRET=...
```

The client secret belongs only in the root `.env`; never put it in an `apps/web/PUBLIC_*`
variable. Restart the local stack after changing provider configuration or credentials:

```sh
./node_modules/.bin/supabase stop
./node_modules/.bin/supabase start
./node_modules/.bin/supabase status --output env
```

Copy the reported API URL and publishable key (or legacy anon key) into the ignored
`apps/web/.env.local`, using the names documented in `apps/web/.env.example`. Then run the web app:

```sh
npm run dev
```

Open `http://localhost:4323/login/`. GitHub redirects to local Supabase Auth first, and Supabase
then redirects to `http://localhost:4323/auth/callback`. The callback exchanges the PKCE code for
the cookie-backed session. The local provider configuration does not configure a linked hosted
project; enable GitHub and configure its hosted callback separately in the Supabase Dashboard.

### Seeded local personas

Real GitHub OAuth is useful for provider testing, but it is slow for developing each application
state. To use the seeded users instead, copy the local secret/service-role key reported by
`supabase status --output env` into the server-only `SUPABASE_SECRET_KEY` variable in
`apps/web/.env.local`, and set:

```env
PUBLIC_AUTH_MODE=local
```

Restart the web app and open `http://localhost:4323/login/`. The login page offers these fixed
personas:

- `emptyLearner` — no membership and no access request
- `pendingLearner` — a pending request for `test-course-a-local`
- `memberCourseA` — active learner membership for `test-course-a-local` only
- `memberCourseB` — active learner membership for `test-course-b-local` only
- `memberBothCourses` — active learner membership for both test courses
- `instructor` — instructor membership for `test-course-a-local`
- `owner` — owner of both seeded test courses

The picker does not accept arbitrary user IDs or email addresses. The server maps the fixed persona
key to a seeded user, asks Supabase Auth Admin for a one-time magic-link token, and immediately
redeems it through `/auth/callback`. The Admin key stays server-side. Resetting the local database
recreates all seven personas and their course states:

```sh
./node_modules/.bin/supabase db reset --local --yes
```

Set `PUBLIC_AUTH_MODE=github` or remove it when you want the normal GitHub button again. Local mode
is disabled in production builds. Astro injects the persona endpoint only during `astro dev`, so
the endpoint and Admin client are absent from the production route manifest and bundle; the dev
endpoint also only responds on loopback hosts.

After a first login, `/desk/` verifies the session and should open. Course MDX routes also call
`public.list_my_courses()` and return `403 Course access required` until that GitHub identity has an
active membership for the exact `offering_key`; the returned `course_definition_key` selects the
shared MDX definition and `course_definition_release_id` identifies its exact compiler release only
after offering authorization succeeds. Login by itself intentionally grants no course access.

`db reset` recreates the local database, applies every migration in order, runs `seed.sql`, and
loads the custom roles from `roles.sql`. The generated seed is produced from the schema-aware
`seed.template.sql` and the fixture data in `supabase/dev-personas.json`; regenerate it after
changing either file:

```sh
npm run supabase:fixtures
./node_modules/.bin/supabase db reset --local --yes
```

Use `migration up --local` when you only want to apply pending migrations without resetting local
data.

## Declarative schema workflow

The files in `schemas/` are the source of truth for the application database. Edit those files
when changing tables, functions, policies, privileges, or other database objects, then generate a
versioned migration from the declared state:

```sh
./node_modules/.bin/supabase db schema declarative sync \
  --name describe_the_change \
  --no-apply \
  --strict-coverage
```

Review the generated file in `migrations/`, commit it together with the schema change, and verify
the complete chain with `db reset` and `test db`. The pinned CLI uses `db schema declarative sync`
for this workflow; its legacy `db diff` command does not consume `schema_paths`. Data changes are
not represented by declarative schema diffs. This initial baseline intentionally contains no data
reconciliation because the database is new; add an explicit migration for any future deployment
that must reconcile pre-existing Auth rows.

Review generated ACLs carefully. The initial baseline includes a small manual ACL guard around
function ownership because pg-delta cannot represent the temporary schema `CREATE` privilege
needed during that transfer, and schema privileges are not fully diffed.

The custom database roles are managed in `roles.sql`. Include them when pushing to a remote
project:

```sh
./node_modules/.bin/supabase db push --linked --include-roles
```

## Future schema changes

1. Edit the desired state in `schemas/*.sql`.
2. Generate a migration with the command above.
3. Review both the schema diff and generated migration, especially grants, RLS, policies, and
   `security definer` functions.
4. Verify the complete chain and regenerate the web client's database types:

```sh
./node_modules/.bin/supabase db reset --local --yes
./node_modules/.bin/supabase test db --local
./node_modules/.bin/supabase db lint --local --fail-on error
./node_modules/.bin/supabase db advisors --local --type security --level info
./node_modules/.bin/supabase db schema declarative sync \
  --no-apply --no-cache --strict-coverage
npm run supabase:types
```

The final sync should report `No schema changes found`. Keep migrations that have been deployed;
future production changes must be forward migrations. Only squash/delete migration history before
the first remote deployment, as was done for this initial baseline.

`npm run supabase:types` reads the running local database and mechanically replaces
`apps/web/src/lib/supabase/database.types.ts`. Commit that generated file with the schema and
migration that produced it; never hand-edit it.

Data changes (`insert`, `update`, `delete`) are not generated by declarative schema diffs. The
development personas above belong in `seed.sql`; create a separate reviewed migration for any
required production data transformation or one-time reconciliation.

## Data API deny-by-default

The application exposes authenticated RPCs, not direct table access. The declarative schema
revokes table, sequence, and function defaults from `anon`, `authenticated`, and `service_role`.
The declarative schema is the source of truth; generate and review the corresponding migration
through the repository's declarative workflow before deploying it. New access must be granted
explicitly alongside its RLS policies.

For local Supabase, `config.toml` sets `auto_expose_new_tables = false`. This is a CLI/local
setting, not a Cloud project setting. For a hosted project, disable **Automatically expose new
tables and functions** in Dashboard → Integrations → Data API, then push the migration:

```sh
./node_modules/.bin/supabase link --project-ref <PROJECT_REF>
./node_modules/.bin/supabase db push --linked --include-roles
```

Do not use `--include-seed` for Cloud or production. For the NixOS self-host, apply the same
migrations through a protected PostgreSQL connection after `supabase.service` is running. The
self-hosted PostgREST configuration is narrowed to `PGRST_DB_SCHEMAS=public` in
`infra/nix/supabase.env`; deploy the NixOS configuration and restart `supabase.service` after
changing it. Keep ports 5432/6543 restricted to an administrator CIDR or use an SSH tunnel.

## Remote deployment

Run these once for a new checkout/project, then use `db push` for releases:

```sh
./node_modules/.bin/supabase login
./node_modules/.bin/supabase link --project-ref "$SUPABASE_PROJECT_REF"
./node_modules/.bin/supabase migration list --linked
./node_modules/.bin/supabase db push --linked --include-roles --dry-run
./node_modules/.bin/supabase db push --linked --include-roles
./node_modules/.bin/supabase migration list --linked
```

Do not pass `--include-seed` for production. `seed.sql` is for local/test data.

## Access and RLS audit

The read-only [audit_access.sql](./audit_access.sql) query reports effective schema, table/view,
sequence, and function privileges for `anon`, `authenticated`, `service_role`, and the two
application roles. It also reports RLS status, policies, role attributes, role memberships, and
default privileges. Effective privileges include access inherited through `PUBLIC`.

```sh
# Local database
./node_modules/.bin/supabase db query --local --file supabase/audit_access.sql

# Linked remote database
./node_modules/.bin/supabase db query --linked --file supabase/audit_access.sql

# Supabase security advisors
./node_modules/.bin/supabase db advisors --local --type security --level info
./node_modules/.bin/supabase db advisors --linked --type security --level info

# Role definitions and API-exposed schemas
./node_modules/.bin/supabase db dump --local --role-only
rg -n '^\[api\]|^schemas\s*=' supabase/config.toml
```

The current API exposure is configured in `config.toml`: `public` and `graphql_public` are
exposed; `private` is not. Public functions with effective `EXECUTE` access are candidates for
PostgREST `/rest/v1/rpc/<function>` routes. The built-in `graphql_public.graphql` function belongs
to the separate GraphQL endpoint, not PostgREST.
