# GitHub App and OAuth automation

```txt
manifest / bash
       │
bootstrap once
       ↓
GitHub App
APP_ID + private key
       │
┌─────────┼─────────┐
↓         ↓         ↓
org-a     org-b     org-c
install   install   install
│         │         │
IAT       IAT       IAT
│         │         │
└────── worker ─────┘
```

## OCI access-worker image

`flake.nix` builds a small Linux OCI image for Podman. The default `image` uses
this checkout; `image-remote` uses the revision pinned in `flake.lock`.

```sh
# On a native Linux host, #image selects the matching supported architecture.
nix build ./infra/github/access-worker#image
podman load < result
```

The flake exposes both `x86_64-linux` and `aarch64-linux`. Build an explicit
target when the host is macOS or when using a remote Linux builder:

```sh
nix build ./infra/github/access-worker#packages.aarch64-linux.image
# or:
nix build ./infra/github/access-worker#packages.x86_64-linux.image
podman load < result
```

On Apple Silicon, build the `aarch64-linux` image on an ARM64 Linux VM or
remote Nix builder; the macOS host itself is not the Linux image builder.

The image runs `poll --watch --interval-seconds 30` by default. Pass another
worker command after the image name for a one-off operation.

### Configure and run

Store the worker configuration in an encrypted SOPS dotenv or YAML file. It
needs `DATABASE_URL` and either `GITHUB_TOKEN`, or the GitHub App client ID
(or numeric App ID), installation ID, and private key. See the
[worker README](../../../crates/ainigma-course-access-worker/README.md) for all
options.

For YAML used with `sops exec-env`, keep the environment variables at the
top level as scalar values. Nested mappings cannot be exported as environment
variables. An email-batch test can use a multiline scalar:

```yaml
RUN_EMAIL_TEST_SETUP: "1"
TEST_EMAILS: |
  student-01@example.edu
  student-02@example.edu
  student-03@example.edu
```

The test entrypoint runs only when `RUN_EMAIL_TEST_SETUP=1`. It runs the
bundled production-table fixture with `DATABASE_ADMIN_URL`, resolves
`TEST_OFFERING_KEY`, and starts the normal polling worker with automatic
repository provisioning enabled. It requires these additional top-level
values: `TEST_OFFERING_KEY`, `TEST_ORGANIZATION_ID`,
`TEST_ORGANIZATION_HANDLE`, `TEST_TEMPLATE_OWNER`, `TEST_TEMPLATE_REPOSITORY`,
`TEST_EMAIL_DOMAIN`, and `TEST_OWNER_AUTH_USER_ID`.

The database must be reachable from the Podman network and the `DATABASE_URL`
login must be a member of `ainigma_external_provisioning_worker`. That role
limits the worker to its provisioning RPCs.

Mount the encrypted file read-only and mount the age identity as a Podman
secret:

```sh
podman secret create ainigma-access-worker-age-key /secure/path/age-key.txt

podman run --rm --name ainigma-course-access-worker \
  --secret ainigma-access-worker-age-key,type=mount,target=/run/secrets/sops-age-key \
  --volume "./secrets/worker.env:/run/secrets/worker.env:ro,Z" \
  --env SOPS_SECRETS_FILE=/run/secrets/worker.env \
  --env SOPS_AGE_KEY_FILE=/run/secrets/sops-age-key \
  --env RUST_LOG=info \
  localhost/ainigma-course-access-worker:latest
```

`SOPS_AGE_KEY_FILE` is only the path to the mounted identity. At startup,
`sops exec-env` decrypts the configuration in memory and replaces itself with
the worker; no plaintext dotenv file is written to the image or container
layer. The decrypted database and GitHub values remain in the worker process
for its lifetime, so do not pass their values with `podman --env`.

After `Cargo.lock` is available in the upstream revision, refresh the optional
remote source with:

```sh
nix flake update ainigma-remote --flake ./infra/github/access-worker
```
