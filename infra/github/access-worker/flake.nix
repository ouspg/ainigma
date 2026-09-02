{
  description = "OCI image for the Ainigma GitHub course access worker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # The default source is the checkout containing this deployment flake.
    ainigma-local = {
      url = "path:../../..";
      flake = false;
    };

    # Use the locked upstream source when building independently of a checkout.
    ainigma-remote = {
      url = "github:ouspg/ainigma";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      ainigma-local,
      ainigma-remote,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      packagesFor =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          workerFor =
            source:
            pkgs.rustPlatform.buildRustPackage {
              pname = "ainigma-course-access-worker";
              version = "0.1.0";
              # A flake input is already an immutable Nix source. For the local
              # input, Nix uses the checked-out repository and respects .gitignore.
              src = source;
              cargoLock.lockFile = source + "/Cargo.lock";
              cargoBuildFlags = [
                "--package"
                "ainigma-course-access-worker"
              ];
              cargoTestFlags = [
                "--package"
                "ainigma-course-access-worker"
              ];
            };

          entrypointFor =
            source:
            let
              testFixturePath = source + "/crates/ainigma-course-access-worker/tests/real_github_email_repository_setup.sql";
              hasTestFixture = builtins.pathExists testFixturePath;
              testFixture = if hasTestFixture then testFixturePath else "/dev/null";
            in
            pkgs.writeShellApplication {
              name = "ainigma-course-access-worker-entrypoint";
              runtimeInputs = [ pkgs.postgresql pkgs.sops ];
              text = ''
                if [ -n "''${SOPS_SECRETS_FILE:-}" ] && [ -z "''${AINIGMA_SOPS_ENV_LOADED:-}" ]; then
                  if [ ! -r "$SOPS_SECRETS_FILE" ]; then
                    echo "SOPS_SECRETS_FILE is not readable: $SOPS_SECRETS_FILE" >&2
                    exit 1
                  fi

                  # Decrypt only into the environment of this process tree. The
                  # marker prevents the re-executed entrypoint from decrypting again.
                  export AINIGMA_SOPS_ENV_LOADED=1
                  command_string=""
                  for argument in "$0" "$@"; do
                    printf -v quoted_argument '%q' "$argument"
                    command_string+=" $quoted_argument"
                  done
                  exec sops exec-env --same-process "$SOPS_SECRETS_FILE" "$command_string"
                fi

                if [ "''${RUN_EMAIL_TEST_SETUP:-}" = "1" ]; then
                  if [ "${if hasTestFixture then "0" else "1"}" = "1" ]; then
                    echo "this worker image does not contain the email test fixture" >&2
                    exit 1
                  fi

                  : "''${DATABASE_ADMIN_URL:?DATABASE_ADMIN_URL is required for email test setup}"
                  : "''${TEST_OFFERING_KEY:?TEST_OFFERING_KEY is required for email test setup}"
                  : "''${TEST_ORGANIZATION_ID:?TEST_ORGANIZATION_ID is required for email test setup}"
                  : "''${TEST_ORGANIZATION_HANDLE:?TEST_ORGANIZATION_HANDLE is required for email test setup}"
                  : "''${TEST_TEMPLATE_OWNER:?TEST_TEMPLATE_OWNER is required for email test setup}"
                  : "''${TEST_TEMPLATE_REPOSITORY:?TEST_TEMPLATE_REPOSITORY is required for email test setup}"
                  : "''${TEST_EMAIL_DOMAIN:?TEST_EMAIL_DOMAIN is required for email test setup}"
                  : "''${TEST_OWNER_AUTH_USER_ID:?TEST_OWNER_AUTH_USER_ID is required for email test setup}"
                  : "''${TEST_EMAILS:?TEST_EMAILS is required for email test setup}"

                  psql "$DATABASE_ADMIN_URL" \
                    -v ON_ERROR_STOP=1 \
                    -v test_offering_key="$TEST_OFFERING_KEY" \
                    -v test_organization_id="$TEST_ORGANIZATION_ID" \
                    -v test_organization_handle="$TEST_ORGANIZATION_HANDLE" \
                    -v test_template_owner="$TEST_TEMPLATE_OWNER" \
                    -v test_template_repository="$TEST_TEMPLATE_REPOSITORY" \
                    -v test_email_domain="$TEST_EMAIL_DOMAIN" \
                    -v test_owner_auth_user_id="$TEST_OWNER_AUTH_USER_ID" \
                    -v test_emails="$TEST_EMAILS" \
                    -f ${testFixture}

                  course_id="$(psql "$DATABASE_ADMIN_URL" -AtX -v ON_ERROR_STOP=1 \
                    -v offering_key="$TEST_OFFERING_KEY" \
                    -c "select id from public.courses where offering_key = :'offering_key'")"
                  if [ -z "$course_id" ]; then
                    echo "could not resolve TEST_OFFERING_KEY to a course ID" >&2
                    exit 1
                  fi

                  exec "$@" --course-id "$course_id" --auto-request-repository
                fi

                exec "$@"
              '';
            };

          imageFor =
            source:
            let
              worker = workerFor source;
              entrypoint = entrypointFor source;
            in
            pkgs.dockerTools.buildLayeredImage {
              name = "ainigma-course-access-worker";
              tag = "latest";
              contents = [
                worker
                entrypoint
                pkgs.cacert
              ];
              config = {
                Entrypoint = [ "${entrypoint}/bin/ainigma-course-access-worker-entrypoint" ];
                Cmd = [
                  "${worker}/bin/ainigma-course-access-worker"
                  "poll"
                  "--watch"
                  "--interval-seconds"
                  "30"
                ];
                Env = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
              };
            };

          worker = workerFor ainigma-local;
          workerRemote = workerFor ainigma-remote;
          image = imageFor ainigma-local;
          imageRemote = imageFor ainigma-remote;
        in
        {
          inherit worker image;
          worker-remote = workerRemote;
          image-remote = imageRemote;
          default = image;
        };
    in
    {
      packages = nixpkgs.lib.genAttrs systems packagesFor;
    };
}
