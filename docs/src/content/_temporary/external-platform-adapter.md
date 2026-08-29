---
title: External platform adapter
---

The course workflow currently uses GitHub, but the worker keeps the workflow
separate from the GitHub HTTP API:

```text
course workflow
    |
    v
ExternalPlatform contract
    |
    +--> GithubPlatform --> GitHub API
    |
    +--> ForgejoPlatform (future example) --> Forgejo API
```

`ExternalPlatform` is the worker contract for the operations that the course
workflow needs:

- send or find an organization invitation;
- resolve a stable external user ID to its current login;
- read one organization snapshot containing members, pending invitations, and
  invitation audit evidence;
- find or create a repository idempotently; and
- grant the learner repository maintenance access.

The invitation and reconciliation code depends only on this contract. The
GitHub request URLs, headers, response decoding, pagination, SSO handling, and
HTTP error mapping live in `github.rs` and `GithubPlatform`.

The database uses provider-neutral names (`external_user_id`,
`external_group_handle`, and `external_invitation_id`) and stores the selected
`provider_kind` and `provider_issuer` with the course-definition group. This
keeps the domain model independent of GitHub while allowing the current
implementation to remain GitHub-specific. A future Forgejo implementation
must still provide the same identity and invitation evidence: the invitation
ID and stable user ID must match before local course access is confirmed.

When a second provider is added, the expected work is:

1. implement `ExternalPlatform` for the provider;
2. map its API responses and permission model to the contract; and
3. select that adapter at worker startup.

If the provider cannot prove the invitation-to-user relationship, its adapter
must report failure or an unsupported capability. It must not confirm access
using only an email address or mutable username.
