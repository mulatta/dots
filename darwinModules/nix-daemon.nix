{
  lib,
  self,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault mkForce;
in
{
  imports = [
    self.inputs.fast-nix-gc.darwinModules.default
  ];

  nixpkgs.overlays = [
    self.overlays.dots
  ];

  # this extends srvos's common settings
  nix = {
    # nix 2.34 has a remote-builder dispatch regression on darwin
    # (https://github.com/NixOS/nix/issues/10451): an aarch64-darwin
    # host refuses to schedule x86_64-linux derivations to a working
    # ssh-ng builder, surfacing as "platform mismatch". Keep the daemon on
    # the latest pre-2.34 release that nixpkgs still ships.
    package = pkgs.nixVersions.nix_2_31;

    # fast-nix-gc and fast-nix-optimise take the same gc.lock; keep stock
    # launchd jobs off so nix-darwin does not run slower duplicate jobs.
    gc.automatic = mkForce false;
    optimise.automatic = mkForce false;

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

  services.fast-nix-gc = {
    enable = mkDefault true;
    automatic = mkDefault true;
    startCalendarInterval = mkDefault [
      {
        Weekday = 1;
        Hour = 0;
        Minute = 15;
      }
    ];
    deleteOlderThan = mkDefault "14d";
  };

  services.fast-nix-optimise = {
    enable = mkDefault true;
    automatic = mkDefault true;
    startCalendarInterval = mkDefault [
      {
        Weekday = 1;
        Hour = 1;
        Minute = 15;
      }
    ];
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
