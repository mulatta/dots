{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ../modules/atuin.nix
    ../modules/direnv.nix
    ../modules/fish.nix
    ../modules/git
    ../modules/helix
    ../modules/llm-agents.nix
    ../modules/modern-unix.nix
    ../modules/nix-utils.nix
    ../modules/packages.nix
    ../modules/starship
    ../modules/xdg.nix
    ../modules/yazi
    ../modules/zellij
  ];

  home = {
    username = lib.mkDefault (builtins.getEnv "USER");
    stateVersion = "25.05";
    homeDirectory = lib.mkDefault (
      if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
    );
  };

  programs.home-manager.enable = true;
  dconf.enable = pkgs.stdenv.isLinux;
  catppuccin.flavor = "mocha";

  nixpkgs.config.allowUnfree = true;
}
