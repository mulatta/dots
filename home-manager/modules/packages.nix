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
      zjstatus
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
      git
      git-lfs
      jjui
      jujutsu

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

      # Security
      age
      age-plugin-yubikey
      rbw
      sops

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
