{ self, pkgs, ... }:
{
  nixpkgs.overlays = [
    self.overlays.dots
  ];

  # this extends srvos's common settings
  nix = {
    package = pkgs.nixVersions.latest;

    gc.automatic = true;
    gc.interval = [
      {
        Weekday = 1;
        Hour = 0;
        Minute = 15;
      }
    ];
    gc.options = "--delete-older-than 14d";

    optimise.automatic = true;

    settings = {
      min-free = toString (10 * 1024 * 1024 * 1024); # 10 GB
      max-free = toString (50 * 1024 * 1024 * 1024); # 50 GB
      # for nix-direnv
      keep-outputs = true;
      keep-derivations = true;

      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.mulatta.io"
      ];
      trusted-substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.mulatta.io"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.mulatta.io-1:DrV+Oy2azNyVKM7ihhD1QoOetRUnW+1G6RWToUpSO4U="
      ];

      trusted-users = [
        "seungwon"
        "root"
      ];

      fallback = true;
      warn-dirty = false;
    };
  };

  launchd.daemons.nix-daemon = {
    serviceConfig.Nice = -10;
  };

  # Cleanup stale gcroots weekly (matches NixOS systemd equivalent)
  launchd.daemons.nix-cleanup-gcroots = {
    command = toString (
      pkgs.writeShellScript "nix-cleanup-gcroots" ''
        # Delete automatic gcroots older than 30 days
        find /nix/var/nix/gcroots/auto /nix/var/nix/gcroots/per-user -type l -mtime +30 -delete 2>/dev/null
        # Delete stale temproots
        find /nix/var/nix/temproots -type f -mtime +10 -delete 2>/dev/null
        # Delete broken symlinks
        find /nix/var/nix/gcroots -xtype l -delete 2>/dev/null
      ''
    );
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 0;
          Minute = 0;
        }
      ];
    };
  };
}
