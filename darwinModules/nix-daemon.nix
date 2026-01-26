{ self, pkgs, ... }:
{
  nixpkgs.overlays = [ self.overlays.default ];

  # this extends srvos's common settings
  nix = {
    package = pkgs.nixVersions.latest;

    gc.automatic = true;
    gc.interval = {
      Hour = 3;
      Minute = 15;
    };
    gc.options = "--delete-older-than 10d";

    settings = {
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
}
