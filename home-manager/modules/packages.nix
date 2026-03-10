{
  pkgs,
  lib,
  inputs,
  ...
}:
{
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
      bat
      bat-extras.batgrep
      bat-extras.batman
      btop
      direnv
      eza
      nix-direnv
      skim
      starship
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
      jjui
      jujutsu
      watchman # filesystem monitor for jj on large repos (nixpkgs)

      # CLI utilities
      ast-grep
      delta
      dust
      fd
      gnugrep
      gnutar
      grex
      gum
      hyperfine
      jq
      ntfy-sh
      ouch
      procs
      ripgrep
      sd
      sqlit-tui
      stow
      uutils-coreutils-noprefix
      xcp
      yq-go
      hexyl

      # Security
      age
      age-plugin-yubikey
      rbw
      sops

      # Radicle
      radicle-node

      # Custom packages
      merge-when-green
      gh-radicle
    ]
    ++ (
      let
        system = pkgs.stdenv.hostPlatform.system;
      in
      [
        # External flakes
        inputs.niks3.packages.${system}.niks3
        inputs.jmt.packages.${system}.jmt
        inputs.zjstatus.packages.${system}.default
        inputs.zsh-helix-mode.packages.${system}.zsh-helix-mode
        inputs.direnv-instant.packages.${system}.default
      ]
    );

  # rbw config: use nix store absolute path for pinentry
  # so rbw-agent can find it regardless of PATH (works on both Linux and macOS)
  xdg.configFile."rbw/config.json".text = builtins.toJSON {
    email = "seungwon@mulatta.io";
    base_url = "https://vaultwarden.mulatta.io";
    lock_timeout = 3600;
    sync_interval = 3600;
    pinentry = "${pkgs.rbw-pinentry}/bin/rbw-pinentry";
  };

  # macOS: symlink ~/Library/Application Support/rbw → ~/.config/rbw
  # rbw uses macOS-native paths, but we want to manage config via ~/.config/rbw
  home.activation.linkRbwConfig = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run rm -rf "$HOME/Library/Application Support/rbw"
      run ln -sfn "$HOME/.config/rbw" "$HOME/Library/Application Support/rbw"
    ''
  );
}
