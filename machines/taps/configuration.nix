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
    ../../nixosModules/auditd.nix
    ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/kernel-hardening.nix
    ../../nixosModules/users.nix
    ../../nixosModules/zerotier.nix
    ./modules/cloudflare-dns.nix
    ./modules/kanidm
    ./modules/coredns.nix
    ./modules/disko-vps.nix
    ./modules/network.nix
    ./modules/nginx
    ./modules/niks3.nix
    ./modules/oauth2-proxy.nix
    ./modules/sshd.nix
    ./modules/stalwart-mail.nix
    ./modules/step-ca.nix
    ./modules/vaultwarden.nix
    ./modules/atuin.nix
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
    btop
  ];

  programs.fish.enable = true;

  system.stateVersion = "25.05";
}
