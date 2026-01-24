{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  sesh = pkgs.writeScriptBin "sesh" ''
    #! /usr/bin/env sh
    ZOXIDE_RESULT=$(zoxide query --interactive)
    if [[ -z "$ZOXIDE_RESULT" ]]; then
      exit 0
    fi
    SESSION_TITLE=$(echo "$ZOXIDE_RESULT" | sed 's#.*/##')
    SESSION_LIST=$(zellij list-sessions -n | awk '{print $1}')
    if echo "$SESSION_LIST" | grep -q "^$SESSION_TITLE$"; then
      zellij attach "$SESSION_TITLE"
    else
      echo "Creating new session $SESSION_TITLE and CD $ZOXIDE_RESULT"
      cd $ZOXIDE_RESULT
      zellij attach -c "$SESSION_TITLE"
    fi
  '';
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
      fzf
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
      ripgrep
      sd
      xcp
      yq-go

      # Security
      age
      age-plugin-yubikey
      sops
      rbw

      # Radicle
      radicle-node

      # Scripts
      sesh
    ]
    ++ [
      # Custom packages
      self.packages.${system}.hm
      self.packages.${system}.jmt
      self.packages.${system}.merge-when-green
      self.packages.${system}.gh-radicle
      self.packages.${system}.rbw-pinentry

      # External flakes
      inputs.niks3.packages.${system}.niks3
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
