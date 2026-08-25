{
  description = "Ainigma NixOS images and host configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Change this release tag explicitly; flake.lock keeps it immutable.
    supabase = {
      url = "github:supabase/supabase?ref=self-hosted%2Fv0.8.0";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      supabase,
      sops-nix,
    }:
    let
      system = "x86_64-linux";
      cscPoutaModules = [
        (
          { modulesPath, ... }:
          {
            imports = [ "${modulesPath}/../maintainers/scripts/openstack/openstack-image.nix" ];
          }
        )
        ./images/csc-pouta.nix
      ];
    in
    {
      nixosConfigurations = {
        csc-pouta-image = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = cscPoutaModules;
        };

        ainigma-data = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit supabase; };
          modules = cscPoutaModules ++ [
            sops-nix.nixosModules.sops
            ./hosts/ainigma-data.nix
          ];
        };
      };

      packages.x86_64-linux = {
        openstack-image = self.nixosConfigurations.csc-pouta-image.config.system.build.openstackImage;
        default = self.packages.x86_64-linux.openstack-image;
      };
    };
}
