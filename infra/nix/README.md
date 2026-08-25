# NixOS image

Build the private CSC cPouta QCOW2 image on an x86_64 Linux builder:

```sh
nix build ./infra/nix#packages.x86_64-linux.openstack-image
```

The image uses cloud-init, creates `cloud-user` from OpenStack metadata, regenerates SSH host keys, and supports ACPI shutdown and volume hotplug. It contains no secrets.

See requirements in here: https://docs.csc.fi/cloud/pouta/adding-images/

## Building initial image

If the current machine is not `x86_64`, the initial image remotely for CSC deployment.
For example:

```sh
nix build \
  --store ssh-ng://nixos \
  ./infra/nix#packages.x86_64-linux.openstack-image \
  --no-link \
  --print-out-paths

# Modify the image path based on previous output
nix copy \
  --no-check-sigs \
  --from ssh-ng://nixos \
  /nix/store/...-nixos-disk-image

# Symlink to output dir with .qcow2 file
ln -s /nix/store/...-nixos-disk-image ./infra/nix/result
ll result/
total 4730112
-r--r--r--  1 root  nixbld   2.2G Jan  1  1970 ainigma-nixos-csc-pouta.qcow2
dr-xr-xr-x  3 root  nixbld    96B Jan  1  1970 nix-support/

```

## Configuring `ainigma-data`

The `ainigma-data` NixOS configuration enables Podman, pins Supabase self-hosted `v0.8.0`, hardens SSH, enables weekly garbage collection and host updates, and opens TCP ports `22`, `443`, `5432`, `6543`, and `8000` in the host firewall.

Pulumi must attach the protected Cinder data volume first and reports its ID and device. A small fail-closed NixOS service accepts only a Cinder-style `/dev/vdb`: it formats a blank disk or relabels the initial ext4 label `vdb` to `ainigma-data`, but refuses every other existing filesystem or label. NixOS then mounts only `LABEL=ainigma-data` at `/var/lib/ainigma`, so later remounts do not depend on the Linux device name. Supabase refuses to initialize or start unless that path is a mount point.

Configure an SSH alias named `ainigma-data` for `cloud-user@<FLOATING_IP>` using Pulumi's current output. The host builds and activates its own configuration:

```sh
nix run nixpkgs#nixos-rebuild -- switch \
  --flake path:./infra/nix#ainigma-data \
  --build-host ainigma-data \
  --target-host ainigma-data \
  --elevate=sudo
```

The complete Supabase configuration is committed as `infra/nix/supabase.env`. SOPS encrypts sensitive values while leaving ordinary configuration readable. To import the working `.env` from a host—or re-encrypt it for a replacement host key—run:

```sh
./infra/nix/scripts/import-supabase-env.sh ainigma-data
```

The script derives the age recipient from the host's SSH ed25519 public key, updates `.sops.yaml`, downloads the root-owned `.env` through `sudo`, and encrypts it atomically. Review and commit both changed files, then deploy with the `nixos-rebuild` command above. The host's SSH private key never leaves the host; sops-nix uses it to decrypt `supabase.env` to `/var/lib/ainigma/supabase/.env`. Supabase will not start if decryption or the Cinder mount fails.

To rotate encrypted values, update the live `.env`, rerun the import script, and commit the resulting encrypted file. Plaintext settings can be edited directly in `infra/nix/supabase.env` because the SOPS MAC covers only encrypted fields.

The database data, Deno cache, storage, and Studio snippets remain under `/var/lib/ainigma/supabase` on the Cinder volume and are not written to the Nix store. Supabase's small image-managed PostgreSQL configuration uses its original Podman named volume so first-run defaults are initialized correctly. Ports `8000`, `5432`, and `6543` are temporarily exposed for setup; restrict `supabaseCidr` in Pulumi and add HTTPS before production use.

Automatic host deployment reads `infra/nix/flake.nix` from the repository's default GitHub branch. Merge this configuration there before relying on `nixos-upgrade.service`.

## Updating Supabase

Review the self-hosting changelog and take a database backup. Then change the `self-hosted/v...` tag in `flake.nix`, refresh only that input, build, and deploy:

```sh
nix flake update supabase --flake ./infra/nix
```

Do not update individual Supabase container tags: each self-hosted release is tested as one coordinated Compose bundle.

## SSH

```bash
ssh cloud-user@86.50.253.185 -i ~/.ssh/ainigma-main.pem
```
