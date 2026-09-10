{
  perSystem =
    { pkgs, ... }:
    let
      # Keep in sync with home/.config/helix/languages.toml.
      helix-lsp-packages = with pkgs; [
        # JSON and Markdown
        vscode-langservers-extracted
        marksman
        harper
        prettier

        # Python
        pyright
        ruff

        # Rust
        rust-analyzer
        clippy
        rustfmt

        # Nix
        nil
        nixd
        nixfmt-rs
        # Available for manual linting; editor integration is pending.
        deadnix
        statix

        # TOML
        taplo

        # Typst
        tinymist
        typstyle

        # YAML
        yaml-language-server
        yamlfmt

        # Shell
        bash-language-server
        shfmt
      ];
    in
    {
      legacyPackages = {
        inherit helix-lsp-packages;
      };

      packages = {
        helix = pkgs.helix;
        # Isolate the repository config for `nix run .#hx`.
        hx = pkgs.callPackage ./helix-standalone.nix {
          inherit helix-lsp-packages;
        };
      };
    };
}
