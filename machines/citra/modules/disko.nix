{ lib, ... }:
let
  disks = {
    primary = {
      device = "/dev/disk/by-id/INSTALL-CITRA-PRIMARY";
      boot = "/boot";
    };
    secondary = {
      device = "/dev/disk/by-id/INSTALL-CITRA-SECONDARY";
      boot = "/boot-secondary";
    };
  };
in
{
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
            keylocation = "prompt";
          };
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
