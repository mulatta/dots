{ pkgs, ... }:
{
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

      # Formatters
      nodePackages.prettier # Multi-language formatter
      alejandra # Nix formatter
      rustfmt # Rust formatter
      shfmt # Shell script formatter
      typstyle # Typst formatter
    ];

    settings = builtins.fromTOML (builtins.readFile ./config.toml);
    languages = import ./languages.nix { inherit pkgs; };
  };
}
