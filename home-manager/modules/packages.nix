{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  nextflow-lsp-jar = pkgs.fetchurl {
    url = "https://github.com/nextflow-io/language-server/releases/download/v25.04.3/language-server-all.jar";
    hash = "sha256-oHdWCsDZoCs0+mfOg+bRqaTayfsAJWzcifflNLvScJs=";
  };

  nextflow-lsp = pkgs.writeShellScriptBin "nextflow-lsp" ''
    exec ${pkgs.jdk17}/bin/java -jar ${nextflow-lsp-jar} "$@"
  '';

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
      atuin
      bat
      bat-extras.batman
      bat-extras.batgrep
      btop
      direnv
      nix-direnv
      eza
      fish
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

      # Editor
      helix

      # LSPs & Formatters
      nil
      nixd
      vscode-langservers-extracted
      yaml-language-server
      bash-language-server
      taplo
      tinymist
      rust-analyzer
      ruff
      pyright
      nextflow-lsp
      jdk17
      nodePackages.prettier
      alejandra
      rustfmt
      shfmt
      typstyle

      # File management
      yazi
      imagemagick
      ffmpegthumbnailer
      unar
      poppler
      glow

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

      # Calendar & Contacts
      vdirsyncer
      khal
      khard

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
      self.packages.${system}.create-gh-app
      self.packages.${system}.rbw-pinentry

      # External flakes
      inputs.llm-agents.packages.${system}.claude-code
      inputs.niks3.packages.${system}.niks3
      inputs.zsh-helix-mode.packages.${system}.zsh-helix-mode
    ]
    ++ lib.optionals (!stdenv.isDarwin) [ fontpreview ];

  # Fish plugins (need nix packaging)
  programs.fish.plugins = [
    {
      name = "fifc";
      inherit (pkgs.fishPlugins.fifc) src;
    }
    {
      name = "git-abbr";
      inherit (pkgs.fishPlugins.git-abbr) src;
    }
    {
      name = "helix-bindings";
      src = pkgs.fetchFromGitHub {
        owner = "tammoippen";
        repo = "fish-helix";
        rev = "8addfe9eae578e6e8efd8c7002c833574824c216";
        hash = "sha256-xTZ9Y/8yrQ7yM/R8614nezmbn05aVve5vMtCyjRMSOw=";
      };
    }
    {
      name = "autopair";
      src = pkgs.fetchFromGitHub {
        owner = "jorgebucaran";
        repo = "autopair.fish";
        rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
        hash = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
      };
    }
  ];

  # Yazi plugins (need nix packaging)
  programs.yazi = {
    enable = true;
    plugins = import ./yazi/plugins.nix { inherit pkgs; };
  };

  # Helix queries for nextflow
  xdg.configFile = {
    "helix/runtime/queries/nextflow".source = "${pkgs.helix}/lib/runtime/queries/groovy";
    "helix/runtime/queries/nextflow-config".source = "${pkgs.helix}/lib/runtime/queries/groovy";
  };
}
