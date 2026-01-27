{ ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      # LSP/formatter tools for HM installation
      legacyPackages.helix-lsp-tools = pkgs.buildEnv {
        name = "helix-lsp-tools";
        paths = with pkgs; [
          # LSPs
          bash-language-server
          marksman
          nil
          nixd
          pyright
          ruff
          rust-analyzer
          taplo
          tinymist
          yaml-language-server
          vscode-langservers-extracted
          # Formatters
          alejandra
          nodePackages.prettier
          shfmt
          typstyle
        ];
      };

      # Standalone helix for `nix run` (separate from HM)
      packages.helix = pkgs.callPackage ./helix-standalone.nix {
        inherit (config.legacyPackages) helix-lsp-tools;
      };
    };
}
