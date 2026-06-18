{
  pkgs,
  inputs,
  ...
}:
{
  # tmux plugins (e.g. tmux-thumbs) ship their .tmux files under
  # share/tmux-plugins/, which is not part of the default output set.
  home.extraOutputsToInstall = [ "share/tmux-plugins" ];

  home.packages =
    with pkgs;
    [
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
      # bat is configured in ../modules/bat.nix (programs.bat).
      btop
      direnv
      eza
      nix-direnv
      sesh
      skim
      starship
      tmux
      tmuxPlugins.tmux-thumbs
      zellij
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
      sqlit-tui
      stow
      uutils-coreutils-noprefix
      xcp
      yq-go
      uv

      # Security
      age
      age-plugin-yubikey
      sops

      # Radicle
      radicle-node

      # Custom packages
      merge-when-green
      miniflux-sync
    ]
    ++ (
      let
        system = pkgs.stdenv.hostPlatform.system;
      in
      [
        # External flakes
        inputs.niks3.packages.${system}.niks3
        inputs.flake-fmt.packages.${system}.default
        inputs.zjstatus.packages.${system}.default
        inputs.zsh-helix-mode.packages.${system}.zsh-helix-mode
        inputs.direnv-instant.packages.${system}.default
      ]
    );
}
