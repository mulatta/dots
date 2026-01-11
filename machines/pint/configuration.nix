{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.nixosModules.default
    self.inputs.nixos-hardware.nixosModules.raspberry-pi-5
    self.inputs.disko.nixosModules.disko
    ../../nixosModules/raspberry-pi
    ../../nixosModules/radicle-mulatta.nix
    ./modules/disko-sd.nix
    ./modules/network.nix
    ./modules/radicle.nix
  ];

  boot.initrd.systemd.enable = lib.mkForce false;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "uas"
    "vc4"
    "pcie_brcmstb"
    "reset-raspberrypi"
    "nvme"
  ];
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA10,115200"
  ];

  hardware.raspberry-pi = {
    boot.enable = true;
    config.all = {
      options = {
        arm_64bit = {
          enable = true;
          value = 1;
        };
        enable_uart = {
          enable = true;
          value = 1;
        };
        avoid_warnings = {
          enable = true;
          value = 1;
        };
        os_check = {
          enable = true;
          value = 0;
        };
        display_auto_detect = {
          enable = true;
          value = 1;
        };
        max_framebuffers = {
          enable = true;
          value = 2;
        };
      };
      dt-overlays.vc4-kms-v3d-pi5.enable = true;
    };
  };

  clan.core.networking.targetHost = "root@pint.x";

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "pint";

  services.openssh.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
    libraspberrypi
    raspberrypi-eeprom
  ];

  programs.fish.enable = true;

  system.stateVersion = "25.05";
}
