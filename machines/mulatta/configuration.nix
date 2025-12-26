{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../nixosModules/users.nix
    self.inputs.apple-silicon.nixosModules.default
    self.inputs.srvos.nixosModules.common
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.sops-nix.nixosModules.sops
  ];

  # sops-nix requires a key source
  sops.age.keyFile = "/var/lib/sops-nix/age-keys.txt";

  clan.core.networking.targetHost = lib.mkForce "root@mulatta.local";

  networking.hostName = "mulatta";

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ self.inputs.apple-silicon.overlays.apple-silicon-overlay ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Peripheral firmware path - use string to avoid pure eval issues
  hardware.asahi.peripheralFirmwareDirectory = "/boot/asahi";
  hardware.asahi.extractPeripheralFirmware = false; # Firmware already extracted on disk

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;
  networking.wireless.iwd = {
    enable = true;
    settings.General.EnableNetworkConfiguration = true;
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  environment.systemPackages = with pkgs; [
    python3
    nixos-rebuild
    parallel
  ];

  srvos.flake = self;

  system.stateVersion = "25.11";
}
