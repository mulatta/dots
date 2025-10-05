{pkgs, ...}: {
  imports = [
    ./atuin.nix
    ./direnv.nix
    ./git
    ./helix
    ./modern-unix.nix
    ./starship
    ./xdg.nix
    ./yazi
    ./stylix.nix
    ./fish.nix
    ./ghostty.nix
    ./nix-utils.nix
    ./zellij
    ./pueue.nix
  ];
  home = {
    username = "seungwon";
    stateVersion = "25.05";
    homeDirectory =
      if pkgs.stdenv.isDarwin
      then "/Users/seungwon"
      else "/home/seungwon";
  };

  programs.home-manager.enable = true;
  catppuccin.flavor = "mocha";

  nixpkgs.config.allowUnfree = true;
}
