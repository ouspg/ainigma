#!/usr/bin/env bash
set -euo pipefail

# ainigma-test
# ainigma-test-worker
ORG="${1:?usage: $0 <org> <app-slug>}"
APP="${2:?usage: $0 <org> <app-slug>}"

echo "=== APP ==="
gh api "/apps/$APP" \
  --jq '{
    app_id: .id,
    client_id,
    slug,
    owner: .owner.login,
    permissions,
    events
  }'

echo
echo "=== INSTALLATION ==="
gh api "/orgs/$ORG/installations" \
  --jq ".installations[]
    | select(.app_slug == \"$APP\")
    | {
        installation_id: .id,
        repository_selection,
        permissions,
        events,
        suspended_at
      }"
