{ ... }:
{
  # Decrypt the committed Supabase .env using the host's own SSH ed25519 key.
  # sops-nix converts the SSH key to an age identity at runtime; nothing is
  # copied elsewhere. The matching age public key (from the host's ed25519 .pub)
  # is committed in infra/nix/.sops.yaml.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Install the decrypted environment into /run so it is never persisted on
  # either the root disk or the Cinder data volume.
  sops.useSystemdActivation = true;

  sops.defaultSopsFile = ../supabase.env;

  sops.secrets.supabase-env = {
    format = "dotenv";
    path = "/run/secrets/supabase.env";
    owner = "root";
    group = "root";
    mode = "0600";
    restartUnits = [ "supabase.service" ];
  };

}
