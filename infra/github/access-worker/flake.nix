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
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      workerFor =
        source:
        let
          sourcePath = builtins.toPath source;
          workspaceSource = lib.fileset.toSource {
            root = sourcePath;
            fileset = lib.fileset.unions [
              (sourcePath + "/Cargo.toml")
              (sourcePath + "/Cargo.lock")
              (sourcePath + "/crates/ainigma-course-access-worker")
            ];
          };
        in
        pkgs.rustPlatform.buildRustPackage {
          pname = "ainigma-course-access-worker";
          version = "0.1.0";
          src = workspaceSource;
          cargoLock.lockFile = workspaceSource + "/Cargo.lock";
          cargoBuildFlags = [
            "--package"
            "ainigma-course-access-worker"
          ];
          cargoTestFlags = [
            "--package"
            "ainigma-course-access-worker"
          ];
        };

      entrypoint = pkgs.writeShellApplication {
        name = "ainigma-course-access-worker-entrypoint";
        runtimeInputs = [ pkgs.sops ];
        text = ''
          if [ -n "''${SOPS_SECRETS_FILE:-}" ]; then
            if [ ! -r "$SOPS_SECRETS_FILE" ]; then
              echo "SOPS_SECRETS_FILE is not readable: $SOPS_SECRETS_FILE" >&2
              exit 1
            fi

            # sops exec-env decrypts only for the worker process. It does not
            # create a plaintext dotenv file in the container filesystem.
            exec sops exec-env --same-process "$SOPS_SECRETS_FILE" "$@"
          fi

          exec "$@"
        '';
      };

      imageFor =
        worker:
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
    in
    {
      packages.${system} = {
        inherit worker;
        image = imageFor worker;
        worker-remote = workerRemote;
        image-remote = imageFor workerRemote;
        default = imageFor worker;
      };
    };
}
