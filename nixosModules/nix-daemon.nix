{
  lib,
  pkgs,
  config,
  self,
  ...
}:
let
  asGB = size: toString (size * 1024 * 1024 * 1024);
  inherit (lib) mkDefault mkForce;
in
{
  services.fast-nix-gc = {
    enable = mkDefault true;
    automatic = mkDefault true;
    dates = mkDefault "03:15";
    deleteOlderThan = mkDefault "14d";
  };

  services.fast-nix-optimise = {
    enable = mkDefault true;
    automatic = mkDefault true;
    dates = mkDefault "04:15";
  };

  nix = {
    # fast-nix-gc and fast-nix-optimise take the same gc.lock; keep stock
    # timers off so srvos/nixpkgs do not run slower duplicate jobs.
    gc.automatic = mkForce false;
    optimise.automatic = mkForce false;

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
        # Delete automatic gcroots older than 14 days (aligned with nix gc and niks3 gc)
        "${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto /nix/var/nix/gcroots/per-user -type l -mtime +14 -delete"
        # Delete stale temproots (created by nix-collect-garbage)
        "${pkgs.findutils}/bin/find /nix/var/nix/temproots -type f -mtime +10 -delete"
        # Delete broken symlinks
        "${pkgs.findutils}/bin/find /nix/var/nix/gcroots -xtype l -delete"
      ];
    };
  };
}
