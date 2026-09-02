---
title: Ainigma course access worker
description: Invitations, access reconciliation, and repository provisioning.
sidebar:
  order: 1
---

<!--# Ainigma course access worker-->

This trusted control-plane worker manages GitHub access for approved course
records. It sends or adopts invitations, reconciles membership, and creates
requested private submission repositories. Offerings using `approval_only`
membership verification create local course membership in the database and
produce no GitHub access work; the worker may still provision their requested
repositories when a verified GitHub identity is linked. It does not create
student memberships or authenticate students.

## Requirements

- A PostgreSQL database with the Ainigma schema and private access RPCs.
- A GitHub App installed in the target organization with only the organization
  and repository permissions this worker needs.
- `DATABASE_URL`, `GITHUB_APP_CLIENT_ID`, `GITHUB_APP_INSTALLATION_ID`, and either
  `GITHUB_APP_PRIVATE_KEY_PATH` or `GITHUB_APP_PRIVATE_KEY`. Set
  `GITHUB_API_URL` only for a GitHub Enterprise API endpoint.
- `GITHUB_APP_ID` is accepted as a fallback issuer when the client ID is not
  available.
- A pre-issued `GITHUB_TOKEN` remains supported for local or legacy setups and
  takes precedence when present.

For deployment, connect with a dedicated `LOGIN` role that is a member of the
schema-provided `ainigma_external_provisioning_worker` role. That role can execute only
the external-access and repository-provisioning RPCs; it has no direct table
access. The login role itself should be `NOSUPERUSER`, `NOCREATEDB`,
`NOCREATEROLE`, `NOREPLICATION`, and `NOBYPASSRLS`.

## Commands

From the repository root:

```sh
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'

# Preferred: authenticate as the installed GitHub App.
export GITHUB_APP_CLIENT_ID='Iv23abc123...'
export GITHUB_APP_INSTALLATION_ID='78901234'
export GITHUB_APP_PRIVATE_KEY_PATH='/run/secrets/ainigma-github-app.pem'

# Alternative for local/legacy testing:
# export GITHUB_TOKEN='...'

# Process invitations, reconcile access, and provision requested repositories once.
cargo run -p ainigma-course-access-worker -- poll

# Keep polling. The interval is clamped to at least one second.
cargo run -p ainigma-course-access-worker -- poll --watch --interval-seconds 30

# Retry one approved access record using its verified email.
cargo run -p ainigma-course-access-worker -- invite \
  --by email --course-id COURSE_UUID --profile-id PROFILE_UUID

# Invite an approved profile to a different configured email domain.
cargo run -p ainigma-course-access-worker -- invite \
  --by email --email person@student.oulu.fi \
  --course-id COURSE_UUID --profile-id PROFILE_UUID

# Adopt an invitation sent manually in GitHub.
cargo run -p ainigma-course-access-worker -- mark-invited \
  --course-id COURSE_UUID --profile-id PROFILE_UUID

# Adopt one sent to an alternate configured email domain.
cargo run -p ainigma-course-access-worker -- mark-invited \
  --by email --email person@student.oulu.fi \
  --course-id COURSE_UUID --profile-id PROFILE_UUID
```

Use `--by external-user-id` when an explicit invitation should target the
stable GitHub user ID instead of an email address. `--course-id` and
`--profile-id` can also filter a polling run.

## GitHub App authentication

When `GITHUB_TOKEN` is absent, startup signs a short-lived JWT with the App's
private key and exchanges it for an installation token. The installation token
is kept in memory and refreshed before GitHub's one-hour expiry.

`GITHUB_APP_CLIENT_ID` is the client ID shown in the GitHub App settings. The
numeric `GITHUB_APP_ID` is accepted as a fallback. Resolve the installation ID
from the organization where the App is installed. Keep the PEM key in a secret
mount or secret manager; do not commit it.

To find the installation ID without an API call, open the organization on
GitHub, choose **Settings → Third-party Access → GitHub Apps**, and click
**Configure** next to the installed App. The final number in the browser URL is
the installation ID:

```text
https://github.com/organizations/ORG/settings/installations/12345678
```

The worker requires all App settings when `GITHUB_TOKEN` is absent: a non-empty
client ID (or numeric App ID), a positive installation ID, and a readable PEM
private key. If a non-empty `GITHUB_TOKEN` is set, the App settings are not
needed and the pre-issued-token flow takes precedence.

## Local smoke test without the web app

The development seed creates a `pendingLearner` profile and a pending request
for `test-course-a-local`. Approve that request as the seeded course owner,
then let the worker process it:

```sh
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
export GITHUB_TOKEN='...'
export GITHUB_ORG_ID='12345678'
export GITHUB_ORG_HANDLE='your-github-organization'
export GITHUB_USER_ID='87654321'

npx supabase db reset --local --yes

psql "$DATABASE_URL" \
  -v ON_ERROR_STOP=1 \
  -v github_org_id="$GITHUB_ORG_ID" \
  -v github_org_handle="$GITHUB_ORG_HANDLE" \
  -v github_user_id="$GITHUB_USER_ID" <<'SQL'
begin;
update private.course_definition_external_groups as organization
set external_group_id = :'github_org_id',
    external_group_handle = :'github_org_handle'
from public.courses as course
where course.course_definition_key = organization.course_definition_key
  and course.offering_key = 'test-course-a-local';
update private.profile_identifiers as identifier
set revoked_at = clock_timestamp()
from private.auth_user_links as link
where link.auth_user_id = '50000000-0000-0000-0000-000000000004'
  and identifier.profile_id = link.profile_id
  and identifier.kind = 'external_user_id'
  and identifier.issuer = 'github.com'
  and identifier.revoked_at is null;
update auth.identities
set provider_id = :'github_user_id',
    identity_data = jsonb_set(
      identity_data,
      '{sub}',
      to_jsonb(:'github_user_id'::text),
      true
    )
where id = '51000000-0000-0000-0000-000000000004'
  and provider = 'github';
select private.sync_auth_identity('51000000-0000-0000-0000-000000000004');
select set_config(
  'request.jwt.claim.sub',
  '50000000-0000-0000-0000-000000000001',
  true
);
set local role authenticated;
select public.approve_course_access_requests(
  'test-course-a-local',
  null
);
reset role;
select access.external_user_id
from private.external_course_access as access
join public.courses as course on course.id = access.course_id
join private.auth_user_links as link on link.profile_id = access.profile_id
where course.offering_key = 'test-course-a-local'
  and link.auth_user_id = '50000000-0000-0000-0000-000000000004';
commit;
SQL

COURSE_ID="$(psql "$DATABASE_URL" -Atc "select id from public.courses where offering_key = 'test-course-a-local'")"

# Option 1: --poll discovers approved records and processes the course.
cargo run -p ainigma-course-access-worker -- poll --course-id "$COURSE_ID"

# Option 2: invite this seeded learner explicitly by email.
PROFILE_ID="$(psql "$DATABASE_URL" -Atc "select link.profile_id from private.auth_user_links as link where link.auth_user_id = '50000000-0000-0000-0000-000000000004'")"
cargo run -p ainigma-course-access-worker -- invite \
  --by email --email learner@student.oulu.fi \
  --course-id "$COURSE_ID" --profile-id "$PROFILE_ID"
```

The seeded GitHub identity and email are local placeholders, so this exercises
the database and worker path but cannot send a real GitHub invitation. For a
real provider test, use a profile whose verified GitHub identity belongs to
the target organization. The sample's `GITHUB_USER_ID` is used only for this
disposable local test: its SQL updates the seeded learner's GitHub identity
before approval, so the later reconciliation sees the same account. Email
domains are configured per course definition in the database and are enforced
by default. Set `email_domain_enforced` to `false` to allow any syntactically
valid email, or add suffixes to
`private.course_definition_external_email_domains`. Do not commit personal
test values.
The worker deliberately does not create profiles:
Auth provisioning creates the profile and its verified identifiers first.

The two UUIDs always identify an approved access record. `--by email` uses the
profile's current verified email unless `--email` supplies another configured
address. The override is recorded with the access record so
retries remain idempotent; it does not create a profile or approve access.

Polling is safe to repeat: existing invitations, memberships, repositories,
and completed jobs are detected rather than duplicated. A learner who is already
in the configured GitHub organization is confirmed from the stable user ID and
active-member snapshot even when no invitation ID exists. Transient provider
failures are recorded; active access is not revoked from one incomplete
snapshot. Keep the token and database URL out of logs and deployment files.

Run tests with:

```sh
cargo test -p ainigma-course-access-worker
```
