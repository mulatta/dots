{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.nixosModules.default
    self.inputs.disko.nixosModules.disko
    self.inputs.srvos.nixosModules.server
    self.inputs.srvos.nixosModules.mixins-nginx
    ../../nixosModules/auditd.nix
    ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/kernel-hardening.nix
    ../../nixosModules/users.nix
    ../../nixosModules/vultr.nix
    ./modules/disko-vps.nix
  ];

  disko.rootDisk = "/dev/vda";

  networking.hostName = "taps";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    self.overlays.dots
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.useDHCP = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    btop
    git
    openldap
    vim
  ];

  programs.fish.enable = true;

  system.stateVersion = "25.05";
}
