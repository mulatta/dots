{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.inputs.apple-silicon.nixosModules.default
    self.inputs.srvos.nixosModules.common
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.sops-nix.nixosModules.sops
    ../../modules/nixos/users.nix
    ../../modules/nixos/disko-zfs.nix
  ];

  disko.rootDisk = "/dev/disk/by-id/nvme-CT2000P3PSSD8_2327E6EA821A";

  clan.core.networking.targetHost = lib.mkForce "root@macaca.local";

  networking.hostName = "macaca";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  environment.systemPackages = [
    pkgs.python3
    pkgs.nixos-rebuild
  ];

  srvos.flake = self;

  system.stateVersion = "25.05";
}
