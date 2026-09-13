{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      helixRuntime =
        pkgs.runCommand "helix-runtime-with-nextflow"
          {
            nativeBuildInputs = [ pkgs.lndir ];
            buildInputs = [ self'.packages.tree-sitter-nextflow ];
          }
          ''
            mkdir -p "$out/grammars" "$out/queries/nextflow"
            lndir -silent ${pkgs.helix.runtime}/grammars "$out/grammars"
            lndir -silent ${pkgs.helix.runtime}/queries "$out/queries"
            ln -s ${self'.packages.tree-sitter-nextflow}/parser "$out/grammars/nextflow.so"
            ln -s ${self'.packages.tree-sitter-nextflow.src}/queries/highlights.scm "$out/queries/nextflow/highlights.scm"
            ln -s ${self'.packages.tree-sitter-nextflow.src}/queries/injections.scm "$out/queries/nextflow/injections.scm"
          '';
      helix = pkgs.symlinkJoin {
        pname = "helix";
        inherit (pkgs.helix-unwrapped) version;
        paths = [ pkgs.helix-unwrapped ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/hx" --set HELIX_RUNTIME "${helixRuntime}"
        '';
        meta = pkgs.helix.meta;
        passthru = {
          runtime = helixRuntime;
          inherit (pkgs.helix) updateScript;
          tree-sitter-grammars = pkgs.helix.tree-sitter-grammars // {
            tree-sitter-nextflow = self'.packages.tree-sitter-nextflow;
          };
        };
      };

      # Keep in sync with home/.config/helix/languages.toml.
      helix-lsp-packages =
        with pkgs;
        [
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

          # TOML and Terraform
          taplo
          terraform-ls

          # TypeScript
          vtsls

          # Go
          go
          gopls
          delve
          golangci-lint
          golangci-lint-langserver
          ginkgo
          gofumpt
          golines
          gomodifytags
          gotests
          gotestsum
          # gopls also ships bin/modernize; let gopls win the collision.
          (pkgs.lib.lowPrio gotools)
          govulncheck
          iferr
          impl

          # Typst
          tinymist
          typstyle

          # YAML
          yaml-language-server
          yamlfmt

          # Shell
          bash-language-server
          shfmt
        ]
        ++ [ self'.packages.nextflow-language-server ];
    in
    {
      legacyPackages = {
        inherit helix-lsp-packages;
      };

      packages = {
        inherit helix;
        # Isolate the repository config for `nix run .#hx`.
        hx = pkgs.callPackage ./helix-standalone.nix {
          inherit helix helix-lsp-packages;
        };
      };
    };
}
