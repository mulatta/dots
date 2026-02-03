{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

in
{
  home.packages =
    with pkgs;
    [
      # Nix tools
      nix-diff
      nix-output-monitor
      nix-prefetch
      nix-tree
      nixd
      nixpkgs-review
      nurl
      nvd
      nh

      # Shell & terminal
      bat
      bat-extras.batman
      bat-extras.batgrep
      btop
      direnv
      nix-direnv
      eza
      zsh
      zsh-autosuggestions
      zsh-fast-syntax-highlighting
      zsh-autopair
      zsh-fzf-tab
      zsh-completions
      skim
      starship
      zellij
      zjstatus
      zoxide
      (if stdenv.isDarwin then ghostty-bin else ghostty)

      # Git
      git
      git-lfs
      gh
      jujutsu
      jjui

      # CLI utilities
      gum
      stow
      delta
      dust
      fd
      grex
      hyperfine
      jq
      ntfy-sh
      ouch
      procs
      sd
      xcp
      yq-go
      uutils-coreutils-noprefix
      gnugrep
      ripgrep
      ast-grep
      gnutar

      # Security
      age
      age-plugin-yubikey
      sops
      rbw

      # Radicle
      radicle-node
    ]
    ++ [
      # Custom packages
      self.packages.${system}.merge-when-green
      self.packages.${system}.gh-radicle

      # External flakes
      inputs.niks3.packages.${system}.niks3
      inputs.jmt.packages.${system}.jmt
      inputs.zsh-helix-mode.packages.${system}.zsh-helix-mode
      inputs.direnv-instant.packages.${system}.default
    ];

  # macOS: symlink ~/Library/Application Support/rbw → ~/.config/rbw
  # rbw uses macOS-native paths, but we want to manage config via ~/.config/rbw
  home.activation.linkRbwConfig = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run rm -rf "$HOME/Library/Application Support/rbw"
      run ln -sfn "$HOME/.config/rbw" "$HOME/Library/Application Support/rbw"
    ''
  );
}
