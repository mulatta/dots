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
    ../modules/packages.nix
    ../modules/starship
    ../modules/xdg.nix
    ../modules/yazi
    ../modules/zellij
    # CLI tools
    ../modules/bat.nix
    ../modules/cli-tools.nix
    ../modules/eza.nix
    ../modules/fzf.nix
    ../modules/zoxide.nix
    # Nix tools
    ../modules/nh.nix
    ../modules/nix-init.nix
    ../modules/nix-tools.nix
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
