{ lib, ... }:
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

    settings = {
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.mulatta.io"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.mulatta.io-1:dZPnrK+1OObojZvijrvXYjRzRNDLUiNVMxd7FgJWcFo="
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
    };
  };
}
