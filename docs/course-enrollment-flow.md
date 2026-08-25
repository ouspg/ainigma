# Course enrollment flow

```mermaid
flowchart TD
    A[GitHub OAuth login] --> B[Profile with stable GitHub user ID]
    B --> C[Request course access<br/> with an optional reason]

    C --> D{Enrollment mode}

    D -->|closed| X[Rejected]
    D -->|allowlist_auto + match| E[Approved automatically]
    D -->|approval_required<br/>or no allowlist match| F[Owner reviews]

    F -->|Reject| X
    F -->|Approve| E

    E --> G[Control plane invites learner<br/>to course GitHub organization]
    G --> H[Learner accepts invite<br/>and completes university SSO]

    H --> I[Signed GitHub organization webhook]
    I --> J[Edge Function enqueues event]
    J --> K[Rust worker checks membership<br/>by numeric user ID]

    K -->|Pending or failed| L[Awaiting GitHub access]
    K -->|Active member| M[Private confirmation RPC]

    M --> N[Active course membership]
    N --> O[Course RPCs and RLS<br/>allow course access]
    N --> Q[Queue repository provisioning]
    Q --> R[Rust worker creates<br/>repos, teams, permissions]
    R --> S[Repository access ready]

    K -->|Membership later removed| P[Suspend or revoke local membership]
    P --> O
```

Owner approval or allowlist approval alone never grants course access. The learner must also be confirmed as a member of the course's GitHub organization.

## Control plane

A trusted Edge Function uses a GitHub App to invite by numeric user ID and accepts signed webhooks. It durably enqueues delivery IDs for a Rust worker (future `pgmq`), which verifies membership and calls the private confirmation/revocation RPC. After membership activation, separate idempotent jobs provision repositories, teams, and permissions. Periodic reconciliation covers missed webhooks; no browser token is trusted.

```
GitHub webhook
  → Supabase Edge Function
  → verify signature
  → enqueue event
  → return 2xx

Rust control-plane worker
  → consume queue
  → call GitHub API
  → verify current membership/IdP state
  → call private confirmation or revocation RPC
```

In short: the Edge Function is the authenticated ingress, the queue is the durable handoff, and the Rust worker performs retries, authorization reconciliation, and GitHub provisioning. PostgreSQL remains authoritative for Ainigma membership; repository provisioning is separate from the membership transaction.

Responsibilities:

- **Edge Function:** verify webhook signatures, deduplicate deliveries, enqueue events, and send invitations.
- **Queue (`pgmq` later):** provide durable handoff and retryable delivery.
- **Rust worker:** call GitHub, reconcile membership, and create repositories, teams, and permissions.
- **PostgreSQL:** decide local access through the private confirmation/revocation RPCs.
