# _αἰνίσσομαι_ - _to speak in riddles_

This software tries to effortlessly turn your cybersecurity assignment dreams into reality—complete with automatic grading.
Think of it as a dynamic CTF challenge generator, but with a twist: every participant gets their own special flag to hunt down. No copy-pasting answers here!

It may or may not be completed. Heavily work-in-progress.

## Manual GitHub access polling

The `ainigma-course-access-worker` binary is a trusted control-plane helper for the current manual
invitation workflow. It does not create student memberships directly and it does not require a
student website auth link. It loads one paginated snapshot of each relevant GitHub organization
(active members and pending invitations), then uses the database confirmation RPC only after
GitHub reports the expected stable user ID as an active member.

It requires a direct PostgreSQL connection and a GitHub token with organization-membership read
access and organization audit-log read access. Database queries use SQLx checked against the local
Supabase schema. Local development uses plain PostgreSQL; configure a TLS connection and a dedicated
least-privilege worker role before using it against a hosted database.

For local development:

```sh
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
```

The SQLx query metadata is generated from that running local database and checked into the
workspace at `.sqlx/`. After changing a declarative schema, reset the local database and refresh
it with:

```sh
export DATABASE_URL='postgres://postgres:postgres@127.0.0.1:54322/postgres'
npm run sqlx:prepare
```

CI can verify that the checked metadata still matches the queries with `npm run sqlx:check`.

After an access request is approved, `poll` automatically invites the verified GitHub identity.
Polling first adopts a matching manually sent email invitation; otherwise it invites by the stable
GitHub user ID. The explicit command uses email by default; use `--by external-user-id` to choose
the stable GitHub user ID explicitly:

```sh
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
export GITHUB_TOKEN='...'
cargo run -p ainigma-course-access-worker -- \
  poll
cargo run -p ainigma-course-access-worker -- \
  invite --by external-user-id --course-id COURSE_UUID --profile-id PROFILE_UUID
```

The explicit `invite` command remains available for a targeted retry or for sending by stable
GitHub user ID.

If the invitation was sent outside the worker, let the worker find the matching pending GitHub
invitation and record its invitation ID:

```sh
cargo run -p ainigma-course-access-worker -- \
  mark-invited --course-id COURSE_UUID --profile-id PROFILE_UUID
```

Use `poll --watch --interval-seconds 30` for a local polling loop. The worker records
`invitation_pending`, `sso_required`, and provider failures. It preserves confirmed access through
transient check failures and revokes it only after three consecutive complete member snapshots omit
the learner. Archived offerings are not reconciled.

Confirmation itself does not create a repository. Once active, a learner may call the authenticated
`request_my_course_repository(offering_key)` RPC from a “Create repository” button. The poller then
creates one private `submissions-<offering_key>-<external_user_handle>` repository per offering/profile
and grants the student `maintain` permission. Existing marked repositories, repeated browser
requests, and repeated worker jobs are safe. Repository retries are bounded; permanent failures are
left `blocked` for operator review. Webhooks can call the same database reconciliation operations
later; they are not required for this workflow.

## Minimum Requirements

1. **Configuration File**: A `.toml` file defining the module, tasks, stages, build logic, and deployment rules.
2. **Task Build**: a shell-based or other type build system for generating task based on flag.
3. **Execution (CLI)**: CLI or other type system to specify tasks to be build with given options

## Configuration File Structure Overview

- `Module`: Structure for the module/course containing Uuid and name
- `Categories`: Logical sections of the course (e.g. “Week 1” or “Basics”)
- `Tasks`: Each Task belongs to a category and consists of:
  - `id`, `name`, `description`, `points` — basic task metadata.
  - `Stages`: Subtasks within a task containing:
    - `id`, `name`, `description`, `weight`
    - `flag` — method for generating user-specific or random flags.
  - `Build`: Build Instructions for task
    - `directory` — relative path to the task code.
    - `builder` — either `shell` or other type build specifing the entrypoint file.
  - `Build Output`: Specifies the files or resources produced by the build.
    - `resource` — downloadable binary or file.
    - `internal` — used internally (e.g., server script).
    - `readme` — instructions shown to users.
    - `meta` — JSON metadata (key-value config for dynamic tasks).
- `Flag Types`: Defines configurations for flag generation methods
  - `pure_random`: random string with given length.
  - `user_derived`: userid and algorithm based deterministic flags that requires the algorithm and the secret.
  - `rng_seed`: Generates consistent seed from user identity.
- `Deployment`: Configuration for deployment parameters
  - `build_timeout`: Max build time (in seconds).
  - `upload`: AWS S3 options for distributing artifacts:
    - `BUCKET_NAME`, `USE_PRE_SIGNED`, expiration policies, etc.

example configuration file is `course.toml`

### Supported Flag Types:

- user_derived algorithms: `HMAC_SHA3_256`

## Builder

Each task uses a **builder** that defines how the task is build. Different flags should produce different task instructions and answers. Meanwhile same flags should produce same instructions and answers deterministically
One way to achieve this is to utilize flag hash when generating different options for tasks.

### Supported builders

- `shell`: Runs a shell entrypoint (default: `entrypoint.sh`)

### Flags

- `pure_random` is passed as enviroment variable with name `FLAG_PURE_RANDOM_{task_id}`
- `user_derived` is passed as enviroment variable with name `FLAG_USER_DERIVED_{task_id}`
- `rng_seed`: Generates consistent seed from user identity. `FLAG_USER_SEED_{task_id}`

currently `user_derived` and `rng_seed` are functionally identical

## CLI

command line can be accessed by running command `aínigma` and the integrity of configuration file can be tested simply by

`bash aínigma --config <path-to-config>.toml generate --dry-run`

`generate` supports the following commands:

- `--output-dir <DIR>` Optional. Directory to write build files to. If omitted, uses a temp dir.
- `--task <task_id>` Build a specific task by its unique ID.
- `--category <NUMBER>` (Not yet implemented.) Build an entire category based on number.
- `--dry-run` Performs a syntax check on the configuration and pretty prints it.
- `--number <N>` Specifies the number of variants to build

command line also supports task generation to moodle xml file with `moodle` and following command:

- `--category <NAME>` Moodle category name for grouping questions together.
- `--output <FILE>` Name of output XML file (default: quiz.xml).

command line support `upload` to check bucket availability with command:

- `--check-bucket` Ensures the target bucket exists and is accessible.

All of these commands can also be seen with --help command.

## Example of Moodle workflow

```mermaid
flowchart TD
    A[Read TOML configuration] --> B[Generate flag]
    B --> C[Assign flag to each task build]
    C --> D[Run code with flag as environment variable]
    D --> E[Generate Moodle XML file]

```

#### License

<sup>
Licensed under the <a href="LICENSE">MIT License</a>.
</sup>

<br>

<sub>
Unless explicitly stated otherwise, any contribution intentionally submitted for inclusion in this project by you shall be licensed under the MIT License as stated above, without any additional terms or conditions.
</sub>
