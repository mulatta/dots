{
  config,
  lib,
  pkgs,
  ...
}:
let
  disks = {
    primary = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7HENU0YB65570K";
      boot = "/boot";
    };
    secondary = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7HENU0YB65633L";
      boot = "/boot-secondary";
    };
  };
in
{
  clan.core.vars.generators.zfs = {
    files.key.neededFor = "partitioning";
    runtimeInputs = [ pkgs.xkcdpass ];
    script = ''
      xkcdpass -d - -n 8 | tr -d '\n' > "$out/key"
    '';
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = map (disk: {
      path = disk.boot;
      devices = [ "nodev" ];
    }) (lib.attrValues disks);
  };

  disko.devices = {
    disk = lib.mapAttrs (_: disk: {
      type = "disk";
      inherit (disk) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = disk.boot;
              mountOptions = [ "umask=0077" ];
            };
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    }) disks;

    zpool.zroot = {
      type = "zpool";
      mode = "mirror";
      options.ashift = "12";
      rootFsOptions = {
        mountpoint = "none";
        compression = "lz4";
        xattr = "sa";
        atime = "off";
        acltype = "posixacl";
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            encryption = "aes-256-gcm";
            keyformat = "passphrase";
            # disko cannot answer a passphrase prompt; clan uploads the key only for install.
            keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}";
          };
          # Later boots prompt on the console or over initrd ssh.
          postCreateHook = "zfs set keylocation=prompt zroot/root";
        };
        "root/nixos" = {
          type = "zfs_fs";
          mountpoint = "/";
          options."com.sun:auto-snapshot" = "true";
        };
        "root/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        "root/home" = {
          type = "zfs_fs";
          mountpoint = "/home";
          options."com.sun:auto-snapshot" = "true";
        };
        "root/tmp" = {
          type = "zfs_fs";
          mountpoint = "/tmp";
        };
      };
    };
  };
}
