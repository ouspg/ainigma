---
title: Ainigma course access worker
description: Invitations, access reconciliation, and repository provisioning.
sidebar:
  order: 1
---

<!--# Ainigma course access worker-->

This trusted control-plane worker currently manages GitHub access for approved
course records. It sends or adopts invitations, reconciles membership, and
creates private submission repositories for explicit requests or opt-in
automatic provisioning. Offerings using
`approval_only` membership verification create local course membership in the
database and produce no GitHub access work; the worker may still provision
their requested repositories when a verified GitHub identity is linked. Both
modes still require an approved access request. The database contract is
provider-neutral, but GitHub is currently the only external-platform adapter
implemented by this worker. It does not create student memberships or
authenticate students.

## Requirements

- A PostgreSQL database with the Ainigma schema and private access RPCs.
- A GitHub App installed in the target organization with only the organization
  and repository permissions this worker needs, including repository
  Administration: write and Contents: read for template generation.
- A public GitHub repository marked as a template. Configure its owner and name
  on each course definition; the template may belong to a different
  organization than the target course organization.
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

# Also queue a repository whenever external course access is confirmed.
cargo run -p ainigma-course-access-worker -- poll \
  --auto-request-repository

# Limit automatic repository requests to one offering while testing.
cargo run -p ainigma-course-access-worker -- poll \
  --course-id COURSE_UUID --auto-request-repository --watch

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

## Real GitHub email-batch test

This test uses the normal production worker and real GitHub side effects. Use a
disposable GitHub organization and public template repository. The setup SQL
updates the selected test offering, configures the target organization and
template, enables an exact allowed email domain, creates local Auth users and
profiles, seeds approved access requests, and queues the real repository jobs.

The setup file is
[`real_github_email_repository_setup.sql`](</Users/nicce/teaching/ainigma/crates/ainigma-course-access-worker/tests/real_github_email_repository_setup.sql>).
It is a disposable fixture, not a schema migration. Do not run it against a
production offering or commit real student addresses.

### 1. Prepare GitHub

Create or select:

- a disposable target organization, for example `ainigma-course-access-test`;
- a public repository marked as a template, for example
  `ainigma-course-templates/course-submission-template`;
- test mailboxes that can receive GitHub invitations, such as
  `student-01@students.example.edu` through `student-50@students.example.edu`.

Install the GitHub App in the target organization with Organization members:
read and write, Repository administration: write, and Repository contents:
read. These permissions cover invitation/member reconciliation, template
repository generation, and granting repository access. A pre-issued token may
be used for local testing instead, but it must have equivalent permissions.

### 2. Configure the database and worker

For the local Supabase database:

```sh
export DATABASE_ADMIN_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
export DATABASE_URL="$DATABASE_ADMIN_URL"

# Use either a GitHub App or a disposable token.
export GITHUB_APP_CLIENT_ID='Iv23abc123...'
export GITHUB_APP_INSTALLATION_ID='78901234'
export GITHUB_APP_PRIVATE_KEY_PATH='/run/secrets/ainigma-github-app.pem'
# export GITHUB_TOKEN='ghp_...'

export TEST_OFFERING_KEY='test-course-a-local'
export TEST_ORGANIZATION_ID='12345678'
export TEST_ORGANIZATION_HANDLE='ainigma-course-access-test'
export TEST_TEMPLATE_OWNER='ainigma-course-templates'
export TEST_TEMPLATE_REPOSITORY='course-submission-template'
export TEST_EMAIL_DOMAIN='students.example.edu'
export TEST_OWNER_AUTH_USER_ID='50000000-0000-0000-0000-000000000001'
export TEST_EMAILS='student-01@students.example.edu
student-02@students.example.edu
student-03@students.example.edu'
```

`TEST_OWNER_AUTH_USER_ID` is the seeded course-owner Auth user. For another
database, replace it with the Auth user ID of an owner profile for the selected
offering. The worker connection used in deployment should be the restricted
login role that is a member of `ainigma_external_provisioning_worker`; the
admin connection is only for this fixture.

### 3. Seed the real application tables

Reset a disposable local database, then run the fixture:

```sh
npm run supabase:reset

psql "$DATABASE_ADMIN_URL" \
  -v ON_ERROR_STOP=1 \
  -v test_offering_key="$TEST_OFFERING_KEY" \
  -v test_organization_id="$TEST_ORGANIZATION_ID" \
  -v test_organization_handle="$TEST_ORGANIZATION_HANDLE" \
  -v test_template_owner="$TEST_TEMPLATE_OWNER" \
  -v test_template_repository="$TEST_TEMPLATE_REPOSITORY" \
  -v test_email_domain="$TEST_EMAIL_DOMAIN" \
  -v test_owner_auth_user_id="$TEST_OWNER_AUTH_USER_ID" \
  -v test_emails="$TEST_EMAILS" \
  -f crates/ainigma-course-access-worker/tests/real_github_email_repository_setup.sql
```

`TEST_EMAILS` is a newline-separated list. Add all 50 addresses to that value;
every address must end in `$TEST_EMAIL_DOMAIN`. The fixture, worker, and
database all enforce that filter.

The fixture deliberately seeds approved rows instead of calling the browser
approval RPC. This isolates the real worker flow while the approval RPC remains
covered by the SQL authorization tests.

### 4. Run the worker and accept invitations

```sh
COURSE_ID="$(psql "$DATABASE_ADMIN_URL" -Atc \
  "select id from public.courses where offering_key = '$TEST_OFFERING_KEY'")"

cargo run -p ainigma-course-access-worker -- poll \
  --course-id "$COURSE_ID" \
  --auto-request-repository \
  --watch \
  --interval-seconds 60
```

The worker sends one email invitation per seeded profile. As each recipient
accepts the GitHub invitation, polling observes the accepted invitation and
active organization member, binds the returned GitHub user ID to that existing
`profile_id`, activates course membership, queues the repository through the
private enqueue RPC, and provisions a private repository from the public
template. Repository creation and collaborator granting are idempotent.

Inspect progress with:

```sh
psql "$DATABASE_ADMIN_URL" -c "
select profile_id,
       state,
       invitation_target,
       external_invitation_id,
       external_user_id,
       external_user_handle
from private.external_course_access
where course_id = '$COURSE_ID'::uuid
order by invitation_target;

select profile_id,
       state,
       repository_name,
       external_repository_url,
       last_error
from private.course_repository_provisioning
where course_id = '$COURSE_ID'::uuid
order by profile_id;
"
```

Expected states are `invitation_pending` before acceptance, then `active` and
`ready` after acceptance and successful provisioning. Resetting the database
removes local test users, memberships, and jobs, but does not remove GitHub
organization members or repositories; clean those up separately in GitHub.

Run tests with:

```sh
cargo test -p ainigma-course-access-worker
```
