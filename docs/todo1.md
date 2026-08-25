# Next

1. Finalize Increment 1 migration with learner access requests, optional reasons, owner approval/rejection, selected/all bulk actions, and membership audit events.
2. Add trusted course roster/allowlist import and owner-side preauthorization filtering; do not create memberships automatically yet.
3. Run local reset/tests, then deploy migrations remotely.
4. Enable GitHub-only Auth; store client ID/secret in SOPS, configure production and Astro callback URLs.
5. Build web login, course views, learner request flow, and owner approval queue using the RPC-only API.
6. Defer personal invitations, email delivery, and enrollment tokens until the request/approval workflow demonstrates a real need.
