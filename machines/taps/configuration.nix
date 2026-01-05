{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.inputs.disko.nixosModules.disko
    self.inputs.srvos.nixosModules.server
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.srvos.nixosModules.mixins-terminfo
    ../../nixosModules/auditd.nix
    ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/kernel-hardening.nix
    ../../nixosModules/users.nix
    ../../nixosModules/zerotier.nix
    ./modules/atuin-server.nix
    ./modules/authelia
    ./modules/lldap
    ./modules/coredns.nix
    ./modules/disko-vps.nix
    ./modules/network.nix
    ./modules/nginx
    ./modules/niks3.nix
    ./modules/sshd.nix
    ./modules/stalwart-mail.nix
    ./modules/step-ca.nix
    ./modules/vaultwarden.nix
  ];

  clan.core.networking.targetHost = "root@64.176.225.253";

  # Block RFC1918 on ZeroTier to avoid Vultr abuse reports
  services.zerotierone.blockRfc1918Addresses = true;

  disko.rootDisk = "/dev/vda";

  networking.hostName = "taps";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ self.overlays.default ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.useDHCP = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];

  programs.fish.enable = true;

  srvos.flake = self;

  system.stateVersion = "25.05";
}
