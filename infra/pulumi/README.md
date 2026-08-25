# Infrastructure

Pulumi provisions CSC cPouta resources and NixOS configures the hosts.

## Add Pulumi in NixOS with Node support:

```bash
nix profile add nixpkgs#pulumi-bin
set -x PULUMI_IGNORE_AMBIENT_PLUGINS true # Ignore some warnings related to bin locations
```

## Get application secrets from CSC (https://pouta.csc.fi/dashboard/identity/application_credentials/)

1. Create Application Credential for the intended project
2. Download `clouds.yaml`
3. Store it securely, e.g. macOS Keychain or simply locally with some extra permission restrictions (not so secure)

```sh
mkdir -p ~/.config/openstack
chmod 700 ~/.config/openstack
chmod 600 ~/.config/openstack/clouds.yaml
```

```sh
# Load OpenStack OS_* credentials or select a clouds.yaml profile.
set -x OS_CLOUD openstack # Setting env in fish, use cloud named as `openstack` which is the default by csc.fi
pulumi login --local # State in local storage
pulumi -C infra/pulumi stack init dev
# Restrict temporary Supabase ports when an administrator CIDR is known, otherwise allows all
pulumi -C infra/pulumi config set supabaseCidr <ADMIN_IP>/32
# Optional: override the public Supabase URL. Defaults to http://<floating-ip>:8000;
# set this once a domain + TLS termination exist. Also exported as supabaseAuthUrl
# (public URL + /auth/v1) and supabaseSiteUrl (defaults to the public URL).
# Required Cinder volume size in GiB:
pulumi -C infra/pulumi config set dataVolumeSizeGb <SIZE_GB> # (currently set to 40GB)
pulumi -C infra/pulumi preview
pulumi -C infra/pulumi up \
  --logtostderr \
  --verbose 3
```

Pulumi uploads the private QCOW2 from `infra/nix/result`. An unchanged SHA-256 digest is not uploaded again. Existing matching images outside Pulumi state must be imported explicitly.

The protected `ainigma-data` Cinder volume is retained if it is removed from Pulumi or the VM is replaced. Its attachment requests `/dev/vdb`; verify the reported `dataServer.dataVolume.device` output before deploying the NixOS mount. Never commit credentials.
