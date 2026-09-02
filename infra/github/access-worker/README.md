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

`flake.nix` builds the Rust `ainigma-course-access-worker` as a Linux OCI
image. It is designed for Podman on a NixOS (or other Linux) host; it is not a
full NixOS userspace image. Keeping the image as the worker plus its runtime
dependencies makes it substantially smaller and avoids running a nested
`systemd` in the container.

Build and load it on an `x86_64-linux` builder:

```sh
# Default: build the worker from this local checkout.
nix build ./infra/github/access-worker#image
podman load < result
```

The default `image` and `worker` packages use the repository root as a local
flake input, so uncommitted worker changes are included. For a source pinned
by this flake's lock file instead, use the optional remote outputs:

```sh
nix build ./infra/github/access-worker#image-remote
podman load < result
```

`image-remote` and `worker-remote` use the locked `github:ouspg/ainigma`
revision. Refresh it deliberately with `nix flake update ainigma-remote --flake
./infra/github/access-worker`.

The image defaults to the safe, repeatable polling command:

```text
ainigma-course-access-worker poll --watch --interval-seconds 30
```

Pass another worker command after the image name to override that default.
For example, a one-off poll is `... ainigma-course-access-worker poll`.

### Runtime configuration

The worker configuration is taken directly from
[`crates/ainigma-course-access-worker/README.md`](../../../crates/ainigma-course-access-worker/README.md):

| Variable                      | Required when             | Notes                                                        |
| ----------------------------- | ------------------------- | ------------------------------------------------------------ |
| `DATABASE_URL`                | Always                    | Use the dedicated, least-privileged provisioning login role. |
| `GITHUB_TOKEN`                | Token authentication      | Takes precedence over all App settings.                      |
| `GITHUB_APP_CLIENT_ID`        | GitHub App authentication | `GITHUB_APP_ID` is the numeric fallback.                     |
| `GITHUB_APP_INSTALLATION_ID`  | GitHub App authentication | Positive numeric installation ID.                            |
| `GITHUB_APP_PRIVATE_KEY`      | GitHub App authentication | Use this _or_ `GITHUB_APP_PRIVATE_KEY_PATH`, not both.       |
| `GITHUB_APP_PRIVATE_KEY_PATH` | GitHub App authentication | Path to a mounted PEM file.                                  |
| `GITHUB_API_URL`              | Optional                  | Set only for GitHub Enterprise.                              |

`RUST_LOG` may be passed as a normal Podman environment variable. Put all
credentials—and preferably all of the table values—in the encrypted SOPS file.
The image's entrypoint accepts the non-secret `SOPS_SECRETS_FILE` path, runs
`sops exec-env --same-process`, and then replaces itself with the worker.
SOPS exposes the decrypted values only to that worker process; it does not
write a decrypted dotenv file into the image or the container writable layer.

### Run with SOPS and a Podman secret

Use an age identity through a Podman secret. The secret value is mounted as a
file and is never supplied in a process environment variable. The encrypted
SOPS file may be bind-mounted read-only because it contains ciphertext only.

Create the Podman secret once on the host. Store the age identity in a protected
file outside this repository:

```sh
podman secret create ainigma-access-worker-age-key /secure/path/age-key.txt
```

Create an encrypted SOPS dotenv or YAML file containing at least the required
variables. For GitHub App authentication, it normally contains:

```dotenv
DATABASE_URL=postgresql://WORKER_LOGIN:PASSWORD@DATABASE_HOST:5432/postgres
GITHUB_APP_CLIENT_ID=Iv23abc123...
GITHUB_APP_INSTALLATION_ID=78901234
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
```

Then run the image. Replace `./secrets/worker.env` with the encrypted SOPS
file; do not use a decrypted file at that path.

```sh
podman run --rm --name ainigma-course-access-worker \
  --secret ainigma-access-worker-age-key,type=mount,target=/run/secrets/sops-age-key \
  --volume "./secrets/worker.env:/run/secrets/worker.env:ro,Z" \
  --env SOPS_SECRETS_FILE=/run/secrets/worker.env \
  --env SOPS_AGE_KEY_FILE=/run/secrets/sops-age-key \
  --env RUST_LOG=info \
  localhost/ainigma-course-access-worker:latest
```

`SOPS_AGE_KEY_FILE` contains only the path to the mounted identity, not the
identity itself. The age identity remains a runtime-mounted Podman secret, and
the App private key is decrypted only into the worker's process environment.
For a GitHub App PEM mounted separately instead, put the non-secret
`GITHUB_APP_PRIVATE_KEY_PATH` path in the SOPS file and mount that PEM at the
same path with `--secret ... ,type=mount,target=...`.

For a local or legacy pre-issued token, put `DATABASE_URL` and `GITHUB_TOKEN`
in the encrypted file instead. `GITHUB_TOKEN` deliberately takes precedence
over the App variables, matching the worker behavior.

The container has no shell-facing SOPS key material baked into it. Do not pass
`SOPS_AGE_KEY`, `GITHUB_TOKEN`, `DATABASE_URL`, or the GitHub App PEM using
`--env`: those values can be inspected through container metadata while the
container runs. Rotate the Podman secret and re-encrypt the SOPS file when an
identity or credential is replaced.
