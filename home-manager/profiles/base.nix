{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    # Shell & Terminal
    ../modules/atuin.nix
    ../modules/fish.nix
    ../modules/starship
    ../modules/zellij
    ../modules/direnv.nix

    # CLI tools
    ../modules/bat.nix
    ../modules/cli-tools.nix
    ../modules/eza.nix
    ../modules/fzf.nix
    ../modules/zoxide.nix

    # Editors
    ../modules/helix

    # Git & VCS
    ../modules/git

    # Nix tools
    ../modules/nh.nix
    ../modules/nix-init.nix
    ../modules/nix-tools.nix

    # AI & LLM
    ../modules/llm-agents.nix

    # Media
    ../modules/media.nix

    # Password management
    ../modules/bitwarden.nix

    # PIM (Email, Calendar, Contacts)
    ../modules/mail.nix
    ../modules/calendar.nix

    # File management
    ../modules/yazi
    ../modules/xdg.nix

    # Misc
    ../modules/packages.nix
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
