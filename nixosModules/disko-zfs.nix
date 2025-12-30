{
  lib,
  config,
  pkgs,
  ...
}:
{
  options = {
    disko.rootDisk = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0n1";
      description = "The device to use for the disk.";
    };
  };
  config = {
    # ZFS requires unique hostId per machine
    clan.core.vars.generators.hostId = {
      files.id.secret = false;
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n' > "$out"/id
      '';
    };
    networking.hostId = builtins.readFile config.clan.core.vars.generators.hostId.files.id.path;

    disko.devices = {
      disk = {
        system = {
          device = config.disko.rootDisk;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                type = "EF02";
                size = "1M";
              };
              ESP = {
                type = "EF00";
                size = "1G";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "defaults"
                    "umask=0077"
                  ];
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
        };
      };
      zpool = {
        zroot = {
          type = "zpool";
          rootFsOptions = {
            compression = "lz4";
            xattr = "sa";
            atime = "off";
            acltype = "posixacl";
            "com.sun:auto-snapshot" = "false";
          };
          options.ashift = "12";

          datasets = {
            "docker".type = "zfs_fs";
            "root".type = "zfs_fs";
            "root/nixos" = {
              type = "zfs_fs";
              mountpoint = "/";
              options."com.sun:auto-snapshot" = "true";
            };
            "root/tmp" = {
              type = "zfs_fs";
              mountpoint = "/tmp";
              options.sync = "disabled";
            };
          };
        };
      };
    };
  };
}
