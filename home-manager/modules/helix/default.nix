{pkgs, ...}: let
  nextflow-lsp-jar = pkgs.fetchurl {
    url = "https://github.com/nextflow-io/language-server/releases/download/v25.04.3/language-server-all.jar";
    hash = "sha256-oHdWCsDZoCs0+mfOg+bRqaTayfsAJWzcifflNLvScJs=";
  };

  nextflow-lsp = pkgs.writeShellScriptBin "nextflow-lsp" ''
    exec ${pkgs.jdk17}/bin/java -jar ${nextflow-lsp-jar} "$@"
  '';
in {
  programs.helix = {
    enable = true;
    defaultEditor = true;
    extraPackages = with pkgs; [
      # Language servers
      nil # Nix LSP (legacy)
      nixd # Nix LSP (modern)
      marksman # Markdown LSP
      vscode-langservers-extracted # JSON, HTML, CSS, ESLint LSPs
      yaml-language-server # YAML LSP
      bash-language-server # Bash LSP
      taplo # TOML LSP
      tinymist # Typst LSP
      rust-analyzer # Rust LSP
      ruff # Python linter/formatter
      pyright # Python type checker

      # Nextflow Language Server
      nextflow-lsp
      jdk17 # Java 17 for Nextflow LSP

      # Formatters
      nodePackages.prettier # Multi-language formatter
      alejandra # Nix formatter
      rustfmt # Rust formatter
      shfmt # Shell script formatter
      typstyle # Typst formatter
    ];

    settings = builtins.fromTOML (builtins.readFile ./config.toml);
    languages = import ./languages.nix {inherit pkgs nextflow-lsp;};
  };

  xdg.configFile = {
    "helix/runtime/queries/nextflow".source = "${pkgs.helix}/lib/runtime/queries/groovy";
    "helix/runtime/queries/nextflow-config".source = "${pkgs.helix}/lib/runtime/queries/groovy";
  };
}
