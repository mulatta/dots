{
  lib,
  config,
  ...
}:
{
  options = {
    disko.rootDisk = lib.mkOption {
      type = lib.types.str;
      default = "/dev/mmcblk0";
      description = "The root disk device for Raspberry Pi SD card.";
    };
  };

  config = {
    disko.devices = {
      disk = {
        main = {
          device = config.disko.rootDisk;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              # Firmware partition for Raspberry Pi bootloader
              firmware = {
                priority = 1;
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot/firmware";
                  mountOptions = [
                    "defaults"
                    "umask=0077"
                  ];
                };
              };
              # Root partition
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };
}
