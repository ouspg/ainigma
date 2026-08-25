{ ... }:
{
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    gc = {
      automatic = true;
      dates = "Sun 03:15";
      options = "--delete-older-than 30d";
    };

    optimise = {
      automatic = true;
      dates = [ "Sun 03:45" ];
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "github:ouspg/ainigma?dir=infra/nix#ainigma-data";
    dates = "Sun 04:15";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  boot.tmp.cleanOnBoot = true;

  users.users."cloud-user" = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;


  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      AllowAgentForwarding = false;
      AllowTcpForwarding = "local";
      AllowUsers = [ "cloud-user" ];
      GatewayPorts = "no";
      KbdInteractiveAuthentication = false;
      LoginGraceTime = "30s";
      MaxAuthTries = 3;
      MaxStartups = "10:30:60";
      PasswordAuthentication = false;
      PerSourceMaxStartups = 3;
      PerSourcePenalties = "crash:90s authfail:10s noauth:5s grace-exceeded:30s refuseconnection:30s max:10m min:15s";
      PermitEmptyPasswords = false;
      PermitRootLogin = "no";
      PermitTunnel = false;
      PubkeyAuthentication = true;
      X11Forwarding = false;
    };
  };

  networking.firewall.enable = true;
}
