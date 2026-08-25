#!/usr/bin/env nix-shell
#! nix-shell -i bash -p coreutils gawk gnugrep sops ssh-to-age

set -euo pipefail

host="${1:-ainigma-data}"
remote_user="${REMOTE_USER:-cloud-user}"
case "$host" in
  *@*) ssh_target="$host" ;;
  *) ssh_target="$remote_user@$host" ;;
esac

remote_env="/var/lib/ainigma/supabase/.env"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
nix_dir="$(cd -- "$script_dir/.." && pwd)"
sops_config="$nix_dir/.sops.yaml"
encrypted_env="$nix_dir/supabase.env"

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

ssh_public_key="$temporary_directory/ssh_host_ed25519_key.pub"
plain_env="$temporary_directory/supabase.env.plain"
new_sops_config="$temporary_directory/.sops.yaml"
new_encrypted_env="$temporary_directory/supabase.env"

echo "Reading the SSH host public key from $ssh_target..."
ssh "$ssh_target" 'cat /etc/ssh/ssh_host_ed25519_key.pub' > "$ssh_public_key"
age_recipient="$(ssh-to-age -i "$ssh_public_key")"

case "$age_recipient" in
  age1*) ;;
  *)
    echo "ssh-to-age returned an invalid recipient: $age_recipient" >&2
    exit 1
    ;;
esac

echo "Using age recipient: $age_recipient"

awk -v recipient="$age_recipient" '
  BEGIN { replaced = 0 }
  /^[[:space:]]*-[[:space:]]*&ainigma-data[[:space:]]+age1[[:alnum:]]+[[:space:]]*$/ {
    print "  - &ainigma-data " recipient
    replaced = 1
    next
  }
  { print }
  END {
    if (!replaced) {
      print "Could not find the &ainigma-data age recipient in .sops.yaml" > "/dev/stderr"
      exit 1
    }
  }
' "$sops_config" > "$new_sops_config"

echo "Downloading $remote_env from $ssh_target as root..."
ssh "$ssh_target" "sudo -n cat '$remote_env'" > "$plain_env"
chmod 0600 "$plain_env"

for required_key in POSTGRES_PASSWORD JWT_SECRET SUPABASE_PUBLIC_URL; do
  if ! grep -q "^$required_key=" "$plain_env"; then
    echo "Downloaded .env is missing $required_key; refusing to replace local configuration" >&2
    exit 1
  fi
done

echo "Encrypting configured secret fields..."
SOPS_CONFIG="$new_sops_config" sops \
  --encrypt \
  --filename-override supabase.env \
  --output "$new_encrypted_env" \
  "$plain_env"

if ! grep -q '^POSTGRES_PASSWORD=ENC\[' "$new_encrypted_env"; then
  echo "POSTGRES_PASSWORD was not encrypted; refusing to replace local configuration" >&2
  exit 1
fi

chmod 0600 "$new_encrypted_env"
mv "$new_sops_config" "$sops_config"
mv "$new_encrypted_env" "$encrypted_env"

echo "Updated:"
echo "  $sops_config"
echo "  $encrypted_env"
echo
echo "Review the diff, commit both files, then deploy the NixOS configuration."
