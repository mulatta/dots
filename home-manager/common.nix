{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    ./modules/atuin.nix
    ./modules/bat.nix
    ./modules/fonts.nix
    ./modules/helix
    ./modules/yazi
  ];

  xdg.enable = true;

  dconf.enable = lib.mkDefault false;

  home.enableNixpkgsReleaseCheck = false;

  manual.html.enable = false;
  manual.manpages.enable = false;
  manual.json.enable = false;

  home.username = lib.mkDefault "seungwon";
  home.stateVersion = "25.05";
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

  programs.home-manager.enable = true;

  nixpkgs.config = import ./config.nix { };

  nix.package = pkgs.nixVersions.latest;

  # tmux plugins (e.g. tmux-thumbs) ship their .tmux files under
  # share/tmux-plugins/, which is not part of the default output set.
  home.extraOutputsToInstall = [ "share/tmux-plugins" ];

  home.packages = [
    config.nix.package
  ]
  ++ (with pkgs; [
    # Nix tools
    nh
    nix-diff
    nix-output-monitor
    nix-prefetch
    nix-tree
    nixd
    nixpkgs-review
    nurl
    nvd

    # Shell & terminal
    # bat is configured in ./modules/bat.nix (programs.bat).
    btop
    direnv
    eza
    nix-direnv
    sesh
    skim
    starship
    tmux
    tmuxPlugins.tmux-thumbs
    zoxide
    zsh
    zsh-autopair
    zsh-autosuggestions
    zsh-completions
    zsh-fast-syntax-highlighting
    zsh-fzf-tab
    (if stdenv.isDarwin then ghostty-bin else ghostty)

    # Git
    gh
    gh-dash
    git
    git-lfs
    git-absorb
    jujutsu
    mergiraf

    # CLI utilities
    ast-grep
    delta
    dust
    fd
    gnugrep
    gnutar
    grex
    gum
    hexyl
    hyperfine
    jq
    ntfy-sh
    ouch
    procs
    ripgrep
    sd
    sendme
    stow
    uutils-coreutils-noprefix
    uv
    xcp
    yq-go

    # Security
    age
    age-plugin-yubikey
    sops

    # Radicle
    radicle-node

    # Custom packages
    merge-when-green
    miniflux-sync
  ])
  ++ (
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    [
      # External flakes
      inputs.niks3.packages.${system}.niks3
      inputs.flake-fmt.packages.${system}.default
      inputs.zsh-helix-mode.packages.${system}.zsh-helix-mode
      inputs.direnv-instant.packages.${system}.default
    ]
  );

  home.sessionVariables = {
    LC_COLLATE = "C.UTF-8";
    NIKS3_SERVER_URL = "https://niks3.mulatta.io";
  };

  # rbw: headless default (TTY pinentry, 24h agent cache).
  # GUI profiles override `pinentry` to use the custom rbw-pinentry with
  # keyring-backed permanent caching needed for launchd/service automation.
  programs.rbw = {
    enable = true;
    settings = {
      email = "seungwon@mulatta.io";
      base_url = "https://vaultwarden.mulatta.io";
      lock_timeout = 86400;
      sync_interval = 3600;
      pinentry = pkgs.pinentry-curses;
    };
  };
}
