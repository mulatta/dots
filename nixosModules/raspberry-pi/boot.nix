# Raspberry Pi direct kernel boot module
# Based on nixos-raspberrypi
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.hardware.raspberry-pi.boot;
  configTxt = config.hardware.raspberry-pi.config-output;

  configTxtFile = pkgs.writeText "config.txt" configTxt;

  firmwareInstaller = pkgs.writeShellApplication {
    name = "rpi-firmware-installer";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      FIRMWARE_PATH="${cfg.firmwarePath}"
      mkdir -p "$FIRMWARE_PATH"
      cp -f "${configTxtFile}" "$FIRMWARE_PATH/config.txt"

      ${lib.optionalString cfg.installDeviceTree ''
        DTB_SRC="${config.hardware.deviceTree.package}"
        for dtb in "$DTB_SRC"/*.dtb "$DTB_SRC"/broadcom/*.dtb; do
          [ -f "$dtb" ] && cp -f "$dtb" "$FIRMWARE_PATH/"
        done
        if [ -d "$DTB_SRC/overlays" ]; then
          mkdir -p "$FIRMWARE_PATH/overlays"
          for ovr in "$DTB_SRC/overlays"/*; do
            [ -f "$ovr" ] && cp -f "$ovr" "$FIRMWARE_PATH/overlays/"
          done
        fi
      ''}

      ${lib.optionalString cfg.installFirmware ''
        FIRMWARE_SRC="${cfg.firmwarePackage}/share/raspberrypi/boot"
        for f in "$FIRMWARE_SRC"/start*.elf "$FIRMWARE_SRC"/fixup*.dat; do
          [ -f "$f" ] && cp -f "$f" "$FIRMWARE_PATH/"
        done
        [ -f "$FIRMWARE_SRC/bootcode.bin" ] && cp -f "$FIRMWARE_SRC/bootcode.bin" "$FIRMWARE_PATH/"
      ''}
    '';
  };

  kernelInstaller = pkgs.writeShellApplication {
    name = "rpi-kernel-installer";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      TOPLEVEL="$1"
      FIRMWARE_PATH="${cfg.firmwarePath}"

      KERNEL="$(readlink -f "$TOPLEVEL/kernel")"
      INITRD="$(readlink -f "$TOPLEVEL/initrd")"

      cp -f "$KERNEL" "$FIRMWARE_PATH/kernel.img"
      cp -f "$INITRD" "$FIRMWARE_PATH/initrd"

      INIT_PATH="$(readlink -f "$TOPLEVEL/init")"
      { cat "$TOPLEVEL/kernel-params"; echo -n " init=$INIT_PATH"; } > "$FIRMWARE_PATH/cmdline.txt"
    '';
  };

in
{
  options.hardware.raspberry-pi.boot = {
    enable = lib.mkEnableOption "Raspberry Pi boot management";

    firmwarePath = lib.mkOption {
      type = lib.types.str;
      default = "/boot/firmware";
      description = "Path to the firmware partition (FAT32).";
    };

    installDeviceTree = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install device tree files to firmware partition.";
    };

    installFirmware = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Raspberry Pi firmware files (start*.elf, fixup*.dat).";
    };

    firmwarePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.raspberrypifw;
      defaultText = lib.literalExpression "pkgs.raspberrypifw";
      description = "Raspberry Pi firmware package.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;

    hardware.raspberry-pi.config.all.options.kernel = {
      enable = true;
      value = "kernel.img";
    };

    hardware.raspberry-pi.config-extra = lib.mkAfter ''
      initramfs initrd followkernel
    '';

    system.build.installBootLoader = "${lib.getExe kernelInstaller}";
    system.boot.loader.id = "raspberrypi-direct";
    system.boot.loader.kernelFile = pkgs.stdenv.hostPlatform.linux-kernel.target;

    system.activationScripts.raspberryPiFirmware = {
      text = "${lib.getExe firmwareInstaller}";
      deps = [ "specialfs" ];
    };

    system.build.raspberryPiConfigTxt = configTxtFile;
    system.build.raspberryPiKernelInstaller = kernelInstaller;
  };
}
