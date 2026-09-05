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
    self.inputs.fast-nix-gc.nixosModules.default
    self.inputs.srvos.nixosModules.server
    self.inputs.srvos.nixosModules.mixins-nginx
    ../../nixosModules/auditd.nix
    ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/i18n.nix
    ../../nixosModules/journald.nix
    ../../nixosModules/kernel-hardening.nix
    ../../nixosModules/minimal-docs.nix
    ../../nixosModules/nix-daemon.nix
    ../../nixosModules/postgresql.nix
    ../../nixosModules/users.nix
    ../../nixosModules/vultr.nix
    ./modules/atuin.nix
    ./modules/backup.nix
    ./modules/bulwark-webmail.nix
    ./modules/disko.nix
    ./modules/gitea-mq.nix
    ./modules/headscale.nix
    ./modules/kanidm
    ./modules/knot
    ./modules/network.nix
    ./modules/nginx
    ./modules/niks3.nix
    ./modules/nostr-relay.nix
    ./modules/ntfy.nix
    ./modules/oauth2-proxy.nix
    ./modules/postgresql.nix
    ./modules/radicle.nix
    ./modules/radicle-mirror.nix
    ./modules/route96.nix
    ./modules/sshd.nix
    ./modules/stalwart-mail.nix
    ./modules/step-ca.nix
    ./modules/uptermd
    ./modules/vaultwarden.nix
    ./modules/zhost.nix
  ];

  networking = {
    hostName = "cask";
    useDHCP = lib.mkDefault true;
    firewall.enable = true;
  };

  services = {
    openssh.enable = true;

    # Bound local rollback space for write-heavy service datasets. Rustic
    # remains the long-term recovery path.
    zfs.autoSnapshot = {
      frequent = 4;
      hourly = 4;
      daily = 2;
      weekly = 0;
      monthly = 0;
    };
  };

  system.autoUpgrade.enable = true;

  nixpkgs = {
    hostPlatform = "x86_64-linux";
    config.allowUnfree = true;
    overlays = [ self.overlays.dots ];
  };

  environment.systemPackages = with pkgs; [
    btop
    git
    vim
  ];

  programs.fish.enable = true;

  # New host baseline; migrated services keep their own compatibility versions.
  system.stateVersion = "26.05";
}
