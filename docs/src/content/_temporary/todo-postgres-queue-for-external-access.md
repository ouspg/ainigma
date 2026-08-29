---
title: "TODO: queue external-access work with Postgres"
---

## Recommendation

Add Postgres Queue (PGMQ) only for work that should start because of an event:

```text
approved access request ──> invitation queue ──> external-access worker
webhook event             ──> event queue      ──> external-access worker

external membership state ──> periodic batch polling (fallback and reconciliation)
repository request        ──> course_repository_provisioning (existing leased jobs)
```

Do not move the whole worker to a queue. PostgreSQL remains authoritative for
course access, and the existing repository provisioning table already provides
durable jobs, leases, retries, and idempotency.

Until this is implemented, `ainigma-course-access-worker poll` discovers
approved `not_started` access rows and starts their invitations on the next poll.

## Work to do

- Enable and configure the logged PGMQ extension for local and deployed Supabase.
- Create a private invitation queue; do not expose queue tables or management
  functions to browser roles.
- Enqueue an invitation message in the same database transaction that approves
  an access request, including automatic allowlist approval.
- Use a small message containing only identifiers such as `course_id` and
  `profile_id`; reread current state before calling the provider.
- Add worker code to read messages with a visibility timeout, process them
  idempotently, and archive successful messages.
- Keep invitation state and failure details in `external_course_access`.
- Define retry limits, delayed retries, and an operator-visible terminal failure
  state. A queue timeout must not create a duplicate invitation.
- Later, enqueue verified webhook deliveries through the same worker boundary.
- Keep periodic membership polling as a recovery path for missed webhooks and
  as a batched provider API operation.
- Add least-privilege grants and negative authorization tests for queue access.
- Add duplicate-message, worker-crash, visibility-timeout, approval-rollback,
  and already-pending-invitation tests.
- Generate the migration and SQLx metadata through the normal CLI workflow;
  do not edit either by hand.

## Scope estimate

- Invitation queue only: roughly 1–2 days.
- Invitation queue plus webhook delivery and deduplication: roughly 2–4 days.
- Moving repository provisioning to the queue as well: roughly 4–7 days and
  not currently recommended.

The queue is worthwhile before production if invitation creation must happen
immediately after approval. Otherwise, the current database scan is simpler
and sufficient while the system remains small.
