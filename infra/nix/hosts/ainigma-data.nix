{ pkgs, ... }:
{
  imports = [
    ../modules/base.nix
    ../modules/supabase.nix
    ../modules/sops.nix
  ];

  networking.hostName = "ainigma-data";

  systemd.services.ainigma-data-volume-prepare = {
    description = "Prepare the Ainigma Cinder data volume";
    wantedBy = [ "local-fs-pre.target" ];
    requiredBy = [ "var-lib-ainigma.mount" ];
    before = [ "var-lib-ainigma.mount" ];
    after = [ "systemd-udev-trigger.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.gnugrep
      pkgs.gnused
      pkgs.systemd
      pkgs.util-linux
    ];
    script = ''
      require_cinder_disk() {
        serial=$(udevadm info --query=property --name="$1" | sed -n 's/^ID_SERIAL=//p')
        if ! printf '%s\n' "$serial" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]$'; then
          echo "$1 does not have the expected Cinder virtio serial" >&2
          exit 1
        fi
      }

      if [ -b /dev/disk/by-label/ainigma-data ]; then
        require_cinder_disk /dev/disk/by-label/ainigma-data
        exit 0
      fi

      if [ ! -b /dev/vdb ]; then
        echo "No labeled Ainigma volume or bootstrap device /dev/vdb was found" >&2
        exit 1
      fi

      require_cinder_disk /dev/vdb

      fs_type=$(blkid -s TYPE -o value /dev/vdb || true)
      fs_label=$(blkid -s LABEL -o value /dev/vdb || true)

      if [ -z "$fs_type" ]; then
        mkfs.ext4 -L ainigma-data /dev/vdb
      elif [ "$fs_type" = ext4 ] && { [ -z "$fs_label" ] || [ "$fs_label" = vdb ]; }; then
        e2label /dev/vdb ainigma-data
      else
        echo "/dev/vdb has unexpected filesystem type or label; refusing to modify it" >&2
        exit 1
      fi

      udevadm trigger --action=change /dev/vdb
      udevadm settle
    '';
  };

  fileSystems."/var/lib/ainigma" = {
    label = "ainigma-data";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=60s"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    22
    443
    5432
    6543
    8000
  ];
}
