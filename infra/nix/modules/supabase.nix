{
  lib,
  pkgs,
  supabase,
  ...
}:
let
  # Persistent state lives on the attached Cinder volume.
  persistentMount = "/var/lib/ainigma";
  stateDirectory = "${persistentMount}/supabase";
  envFile = "/run/secrets/supabase.env";

  # Public Supabase URLs. Supabase is a headless API/auth backend; the web app
  # users log into is a separate origin.
  publicIp = "86.50.253.185";
  publicUrl = "http://${publicIp}:8000";
  siteUrl = "http://${publicIp}:8000";

  podmanCompose = pkgs.podman-compose.overridePythonAttrs (_: rec {
    version = "1.6.0";
    src = pkgs.fetchPypi {
      pname = "podman_compose";
      inherit version;
      hash = "sha256-yD/ZvLqmNRANWBzlKnpLcS7g1FdIEjKv85Lv4+vFohc=";
    };
    doCheck = false;
  });

  supabaseDocker = pkgs.runCommand "supabase-docker" { } ''
    cp -R ${supabase}/docker "$out"
    chmod -R u+w "$out"

    # add-new-auth-keys.sh normally enables these after generating ES256 keys.
    # Our Compose file is immutable, so enable them during the Nix build.
    # GitHub OAuth is intentionally disabled for now.
    # -e '/^[[:space:]]*#[[:space:]]*GOTRUE_EXTERNAL_GITHUB_ENABLED:/ s/#[[:space:]]*//' \
    # -e '/^[[:space:]]*#[[:space:]]*GOTRUE_EXTERNAL_GITHUB_CLIENT_ID:/ s/#[[:space:]]*//' \
    # -e '/^[[:space:]]*#[[:space:]]*GOTRUE_EXTERNAL_GITHUB_SECRET:/ s/#[[:space:]]*//' \
    # -e '/^[[:space:]]*#[[:space:]]*GOTRUE_EXTERNAL_GITHUB_REDIRECT_URI:/ s/#[[:space:]]*//' \
    sed -i \
      -e '/^[[:space:]]*#GOTRUE_JWT_KEYS:/ s/#//' \
      -e '/^[[:space:]]*#API_JWT_JWKS:/ s/#//' \
      -e '/^[[:space:]]*#JWT_JWKS:/ s/#//' \
      -e '/^[[:space:]]*#SUPABASE_JWKS:/ s/#//' \
      "$out/docker-compose.yml"

      # GitHub OAuth is intentionally disabled for now.
      # GOTRUE_EXTERNAL_GITHUB_ENABLED
      # GOTRUE_EXTERNAL_GITHUB_CLIENT_ID
      # GOTRUE_EXTERNAL_GITHUB_SECRET
      # GOTRUE_EXTERNAL_GITHUB_REDIRECT_URI; do
    for setting in \
      GOTRUE_JWT_KEYS \
      API_JWT_JWKS \
      JWT_JWKS \
      SUPABASE_JWKS; do
      if ! grep -q "^[[:space:]]*$setting:" "$out/docker-compose.yml"; then
        echo "Failed to enable $setting in docker-compose.yml" >&2
        exit 1
      fi
    done

    # Keep mutable state outside the Nix store. All other bind mounts use the
    # immutable, pinned Supabase configuration directly.
    substituteInPlace "$out/docker-compose.yml" \
      --replace-fail "./volumes/snippets" "${stateDirectory}/volumes/snippets" \
      --replace-fail "./volumes/storage" "${stateDirectory}/volumes/storage" \
      --replace-fail "./volumes/db/data" "${stateDirectory}/volumes/db/data" \
      --replace-fail "deno-cache:/root/.cache/deno" "${stateDirectory}/volumes/deno-cache:/root/.cache/deno" \
      --replace-fail "./volumes/" "$out/volumes/"

    sed -i \
      -e "\|$out/volumes/| s/:ro,z$/:ro/" \
      -e "\|$out/volumes/| s/:z$/:ro/" \
      -e "\|$out/volumes/| s/:Z$/:ro/" \
      "$out/docker-compose.yml"

    if grep -q '^[[:space:]]*- \./volumes/' "$out/docker-compose.yml"; then
      echo "An unhandled relative Supabase volume remains" >&2
      exit 1
    fi
  '';

  initializeSupabase = pkgs.writeShellScriptBin "ainigma-supabase-init" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.nodejs_22
        pkgs.openssl
        pkgs.util-linux
      ]
    }

    if [ "$(id -u)" -ne 0 ]; then
      echo "Run ainigma-supabase-init as root" >&2
      exit 1
    fi

    if ! mountpoint --quiet ${persistentMount}; then
      echo "${persistentMount} is not mounted; refusing to write Supabase state to the root disk" >&2
      exit 1
    fi

    if [ -e ${stateDirectory}/.env ]; then
      echo "Refusing to replace the existing Supabase .env" >&2
      exit 1
    fi

    temporary_directory=$(mktemp -d)
    trap 'rm -rf "$temporary_directory"' EXIT

    cp /etc/ainigma/supabase/.env.example "$temporary_directory/.env"
    cp /etc/ainigma/supabase/docker-compose.yml "$temporary_directory/docker-compose.yml"

    (
      cd "$temporary_directory"
      ${pkgs.dash}/bin/dash /etc/ainigma/supabase/utils/generate-keys.sh --update-env >/dev/null
      ${pkgs.dash}/bin/dash /etc/ainigma/supabase/utils/add-new-auth-keys.sh --update-env >/dev/null
      sed -i \
        -e 's|^DOCKER_SOCKET_LOCATION=.*$|DOCKER_SOCKET_LOCATION=/run/podman/podman.sock|' \
        -e 's|^SUPABASE_PUBLIC_URL=.*$|SUPABASE_PUBLIC_URL=${publicUrl}|' \
        -e 's|^API_EXTERNAL_URL=.*$|API_EXTERNAL_URL=${publicUrl}/auth/v1|' \
        -e 's|^SITE_URL=.*$|SITE_URL=${siteUrl}|' \
        -e 's|^ADDITIONAL_REDIRECT_URLS=.*$|ADDITIONAL_REDIRECT_URLS=|' \
        .env
    )

    install -m 0600 "$temporary_directory/.env" ${stateDirectory}/.env.new
    mv ${stateDirectory}/.env.new ${stateDirectory}/.env

    echo "Generated ${stateDirectory}/.env"
    echo "Set the public URLs and authentication settings, then start supabase.service."
  '';
in
{
  assertions = [
    {
      assertion = lib.versionAtLeast podmanCompose.version "1.6.0";
      message = "Supabase self-hosting requires podman-compose 1.6.0 or newer";
    }
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.etc."ainigma/supabase".source = supabaseDocker;

  environment.systemPackages = [
    initializeSupabase
    podmanCompose
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDirectory} 0700 root root -"
    "d ${stateDirectory}/volumes 0750 root root -"
    "d ${stateDirectory}/volumes/db 0750 root root -"
    "d ${stateDirectory}/volumes/db/data 0750 root root -"
    "d ${stateDirectory}/volumes/deno-cache 0750 root root -"
    "d ${stateDirectory}/volumes/storage 0750 root root -"
    "d ${stateDirectory}/volumes/snippets 0750 root root -"
  ];

  systemd.services.supabase = {
    description = "Self-hosted Supabase";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    requires = [ "sops-install-secrets.service" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ supabaseDocker ];
    unitConfig = {
      ConditionPathExists = envFile;
      ConditionPathIsMountPoint = persistentMount;
      RequiresMountsFor = [ persistentMount ];
    };
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = stateDirectory;
      ExecStart = "${podmanCompose}/bin/podman-compose --env-file ${envFile} -f ${supabaseDocker}/docker-compose.yml up -d --wait";
      ExecStop = "${podmanCompose}/bin/podman-compose --env-file ${envFile} -f ${supabaseDocker}/docker-compose.yml down";
      TimeoutStartSec = "30min";
      TimeoutStopSec = "5min";
    };
  };
}
