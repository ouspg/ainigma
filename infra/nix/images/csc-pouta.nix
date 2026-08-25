{ lib, ... }:
{
  system.stateVersion = "26.05";

  image.baseName = "ainigma-nixos-csc-pouta";

  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [
        "OpenStack"
        "ConfigDrive"
        "Ec2"
        "NoCloud"
      ];
      disable_root = true;
      preserve_hostname = false;
      ssh_deletekeys = true;
      ssh_genkeytypes = [
        "ed25519"
        "rsa"
      ];
      users = [ "default" ];
      system_info = {
        distro = "nixos";
        network.renderers = [ "networkd" ];
        default_user = {
          name = "cloud-user";
          gecos = "Cloud user";
          groups = [ "wheel" ];
          lock_passwd = true;
          shell = "/run/current-system/sw/bin/bash";
          sudo = [ "ALL=(ALL) NOPASSWD:ALL" ];
        };
      };
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
      KbdInteractiveAuthentication = false;
    };
  };

  networking.useNetworkd = true;

  # cloud-init is the sole OpenStack metadata agent for CSC compatibility.
  systemd.services.openstack-init.enable = false;
  systemd.services.apply-ec2-data.enable = false;
  systemd.services.amazon-init.enable = false;

  services.acpid.enable = true;
  services.qemuGuest.enable = true;

  boot.kernelModules = [ "acpiphp" ];
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  networking.hostName = lib.mkDefault "";
}
