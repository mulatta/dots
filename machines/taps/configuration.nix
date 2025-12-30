{
  self,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    self.inputs.srvos.nixosModules.server
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.disko.nixosModules.disko
    ../../nixosModules/users.nix
    ../../nixosModules/zerotier.nix
    ../../nixosModules/auditd.nix
    ./modules/sshd.nix # VPS hardening + fail2ban
    ../../nixosModules/kernel-hardening.nix
    ../../nixosModules/auto-upgrade.nix
    ./modules/disko-vps.nix
    ./modules/atuin-server.nix
    ./modules/network.nix
    ./modules/step-ca.nix
  ];
  # sops-nix is managed by clan-core

  # Clan networking - use public IP, change to taps.i after ZeroTier
  clan.core.networking.targetHost = "root@64.176.225.253";

  # Block RFC1918 on ZeroTier to avoid Vultr abuse reports
  # TODO: Enable after ZeroTier is configured
  # services.zerotierone.blockRfc1918Addresses = true;

  # sops-nix keyFile is managed by clan.core.vars.sops

  # VPS uses /dev/vda
  disko.rootDisk = "/dev/vda";

  networking.hostName = "taps";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;

  # Use GRUB for VPS (no EFI)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Network: use systemd-networkd (srvos default)
  # Static IP will be configured via facter.json or manually
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
