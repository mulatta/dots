{
  lib,
  pkgs,
  config,
  self,
  ...
}:
let
  asGB = size: toString (size * 1024 * 1024 * 1024);
  inherit (lib) mkDefault;
in
{
  nix = {
    gc.automatic = mkDefault true;
    gc.dates = mkDefault "monthly";
    gc.options = mkDefault "--delete-older-than 14d";
    gc.randomizedDelaySec = "1h";

    nixPath = [ "nixpkgs=${self.inputs.nixpkgs}" ];

    settings = {
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.mulatta.io"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.mulatta.io-1:DrV+Oy2azNyVKM7ihhD1QoOetRUnW+1G6RWToUpSO4U="
      ];

      system-features = [
        "benchmark"
        "big-parallel"
        "ca-derivations"
        "kvm"
        "nixos-test"
        "recursive-nix"
        "uid-range"
      ];

      # auto-free the /nix/store
      min-free = asGB 10;
      max-free = asGB 50;

      # Hard-link duplicated files
      auto-optimise-store = true;

      # For nix-direnv: keep build outputs and derivations
      keep-outputs = true;
      keep-derivations = true;

      # Trust wheel group users
      trusted-users = [
        "@wheel"
        "root"
      ];

      # Disable dirty git tree warning
      warn-dirty = false;

      # Disable fsync on ZFS (ZFS already guarantees consistency)
      fsync-metadata = lib.mkIf (config.fileSystems."/".fsType == "zfs") false;
    };
  };

  # Cleanup stale gcroots weekly
  systemd.timers.nix-cleanup-gcroots = {
    timerConfig = {
      OnCalendar = [ "weekly" ];
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };

  systemd.services.nix-cleanup-gcroots = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        # Delete automatic gcroots older than 30 days
        "${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto /nix/var/nix/gcroots/per-user -type l -mtime +30 -delete"
        # Delete stale temproots (created by nix-collect-garbage)
        "${pkgs.findutils}/bin/find /nix/var/nix/temproots -type f -mtime +10 -delete"
        # Delete broken symlinks
        "${pkgs.findutils}/bin/find /nix/var/nix/gcroots -xtype l -delete"
      ];
    };
  };
}
