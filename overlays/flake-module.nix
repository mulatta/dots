{ inputs, lib, ... }:
{
  flake.overlays = {
    dots =
      _final: prev:
      let
        system = prev.stdenv.hostPlatform.system;
      in
      {
        # qmd: kept in overlay for CUDA override chain (gpu-support.nix)
        qmd = inputs.llm-agents.packages.${system}.qmd;
        # afew: fix pkg_resources deprecation warning (PR #363 merged but not in 3.0.1)
        afew = prev.afew.overridePythonAttrs (old: {
          version = "3.0.2";
          src = prev.fetchFromGitHub {
            owner = "afewmail";
            repo = "afew";
            rev = "23b5aeaa43572a59e95fb00732292087b091d4a1";
            hash = "sha256-RClWSHvyDTJjJsjLXAIAv24TE5NskXLCQ7RcKKt2330=";
          };
          env.SETUPTOOLS_SCM_PRETEND_VERSION = "3.0.2";
          dependencies = (old.dependencies or [ ]) ++ [
            prev.python3Packages.notmuch2
          ];
        });

        # TODO: remove after nixpkgs#489305 is merged
        skim = prev.skim.overrideAttrs (old: {
          checkFlags = (old.checkFlags or [ ]) ++ [
            "--skip"
            "listen_"
          ];
        });

        # Custom packages
        sieve-sync = prev.callPackage ../packages/sieve-sync { };
        merge-when-green = prev.callPackage ../packages/merge-when-green {
          jmt = inputs.jmt.packages.${system}.default;
        };
        claude-code = prev.callPackage ../packages/claude-code {
          claude-code = inputs.llm-agents.packages.${system}.claude-code;
          ck = inputs.llm-agents.packages.${system}.ck;
        };
        claude-md = prev.callPackage ../packages/claude-md { };
        rbw-pinentry = prev.callPackage ../packages/rbw-pinentry { };
        gh-radicle = prev.callPackage ../packages/gh-radicle { };
        email-sync = prev.callPackage ../packages/email-sync {
          claude-code = inputs.llm-agents.packages.${system}.claude-code;
        };
        ntfy-subscribe = prev.callPackage ../packages/ntfy-subscribe { };
        updater = prev.callPackage ../packages/updater { };
        instagram-cli = prev.callPackage ../packages/instagram-cli { };
        radicle-desktop = prev.callPackage ../packages/radicle-desktop { };

        # Tool bundles (moved from helix/yazi flake-modules)
        helix-lsp-tools = prev.buildEnv {
          name = "helix-lsp-tools";
          paths = with prev; [
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

        yazi-plugins =
          let
            plugins = with prev.yaziPlugins; {
              inherit
                chmod
                full-border
                toggle-pane
                diff
                rsync
                miller
                starship
                glow
                git
                piper
                ;
            };
          in
          prev.runCommand "yazi-plugins" { } ''
            mkdir -p $out/share/yazi/plugins
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: pkg: ''
                ln -s ${pkg} $out/share/yazi/plugins/${name}.yazi
              '') plugins
            )}
          '';

        yazi-preview-tools = prev.buildEnv {
          name = "yazi-preview-tools";
          paths = with prev; [
            imagemagick
            ffmpegthumbnailer
            unar
            poppler
            glow
          ];
        };
      }
      // prev.lib.optionalAttrs prev.stdenv.isDarwin {
        systemctl-macos = prev.callPackage ../packages/systemctl { };
        nextcloud-client = prev.callPackage ../packages/nextcloud-client { };
      }
      // prev.lib.optionalAttrs (system == "aarch64-darwin") {
        meetily = prev.callPackage ../packages/meetily { };
      };

    # Requires: dots overlay applied first (provides qmd), cudaSupport=true in nixpkgs config
    llm-agents-cuda = final: prev: {
      qmd = prev.qmd.override {
        cudaSupport = true;
        cudaPackages = final.cudaPackages;
      };
    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.self.overlays.dots
        ];
      };
    };
}
