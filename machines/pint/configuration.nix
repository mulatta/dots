{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.inputs.nixos-hardware.nixosModules.raspberry-pi-5
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.disko.nixosModules.disko
    ../../nixosModules/users.nix
    ../../nixosModules/zerotier.nix
    ../../nixosModules/dns-client.nix
    ./modules/disko-sd.nix
    ./modules/network.nix
  ];

  # Raspberry Pi 5 boot loader (extlinux, not GRUB)
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # raspberry pi kernel doesnot have tpm module
  boot.initrd.availableKernelModules = lib.mkForce [ ];

  clan.core.networking.targetHost = "root@10.80.169.64";

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "pint";

  services.openssh.enable = true;

  # mDNS for local discovery
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
