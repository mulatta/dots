{ pkgs, ... }:
{
  imports = [
    ./atuin.nix
    ./direnv.nix
    ./fish.nix
    ./ghostty.nix
    ./git
    ./helix
    ./modern-unix.nix
    ./nix-utils.nix
    ./packages.nix
    ./starship
    ./stylix.nix
    ./xdg.nix
    ./yazi
    ./zellij
  ];
  home = {
    username = "seungwon";
    stateVersion = "25.05";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/seungwon" else "/home/seungwon";
  };

  programs.home-manager.enable = true;
  dconf.enable = pkgs.stdenv.isLinux;
  catppuccin.flavor = "mocha";

  nixpkgs.config.allowUnfree = true;
}
