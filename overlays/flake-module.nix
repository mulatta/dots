{
  inputs,
  lib,
  ...
}:
{
  flake.overlays = {
    dots =
      final: prev:
      let
        system = prev.stdenv.hostPlatform.system;
        danteZenityPkgs = import inputs.overlay-nixpkgs-dante-zenity {
          inherit system;
          config = {
            allowUnfree = prev.config.allowUnfree or false;
          };
        };
      in
      {
        # qmd: kept in overlay for CUDA override chain (gpu-support.nix)
        qmd = inputs.llm-agents.packages.${system}.qmd;
        nitrous = inputs.nitrous.packages.${system}.default;
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

        miniflux = prev.miniflux.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../packages/miniflux/allow-highlight-trusted-type.patch
            ../packages/miniflux/send-webhook-on-star.patch
          ];
        });

        # Custom packages
        rsshub = prev.callPackage ../packages/rsshub {
          rsshub = prev.rsshub;
        };
        chartdb = prev.callPackage ../packages/chartdb { };
        bulwark-webmail = prev.callPackage ../packages/bulwark-webmail { };
        dbml-cli = prev.callPackage ../packages/dbml-cli { };
        merge-when-green = prev.callPackage ../packages/merge-when-green {
          flake-fmt = inputs.flake-fmt.packages.${system}.default;
        };
        claude-code = prev.callPackage ../packages/claude-code {
          claude-code = inputs.llm-agents.packages.${system}.claude-code;
        };
        claude-md = prev.callPackage ../packages/claude-md { };
        rbw-pinentry = prev.callPackage ../packages/rbw-pinentry { };
        rhwp = inputs.rhwp.packages.${system}.rhwp-cli;
        rhwp-studio = inputs.rhwp.packages.${system}.rhwp-studio;
        email-sync = prev.callPackage ../packages/email-sync { };
        msmtp-with-sent = prev.callPackage ../packages/msmtp-with-sent { };
        n8n-hooks = prev.callPackage ../packages/n8n-hooks { };
        jellyfin-plugin-sso-auth = prev.callPackage ../packages/jellyfin-plugin-sso-auth { };
        slack-manifest-cli = prev.callPackage ../packages/slack-manifest-cli { };
        miniflux-sync = prev.callPackage ../packages/miniflux-sync { };
        ntfy-subscribe = prev.callPackage ../packages/ntfy-subscribe { };
        nostore-preload = prev.callPackage ../packages/nostore-preload { };
        pim = prev.callPackage ../packages/pim {
          calendar-cli = inputs.skillz.packages.${system}.calendar-cli.override {
            msmtp = final.msmtp-with-sent;
          };
          crabfit-cli = inputs.skillz.packages.${system}.crabfit-cli;
          nodePath = "${prev.callPackage ../home/.pi/agent/default.nix { }}/node_modules";
          miniflux-cli = inputs.skillz.packages.${system}.miniflux-cli;
          vikunja-cli = inputs.skillz.packages.${system}.vikunja-cli;
          n8n-hooks = final.n8n-hooks;
          pi = inputs.llm-agents.packages.${system}.pi;
        };
        updater = prev.callPackage ../packages/updater { };
        instagram-cli = prev.callPackage ../packages/instagram-cli { };
        quarkdown = prev.callPackage ../packages/quarkdown { };
        radicle-desktop = prev.callPackage ../packages/radicle-desktop { };

        # Tool bundles (moved from helix/yazi flake-modules)
        helix-lsp-tools = prev.buildEnv {
          name = "helix-lsp-tools";
          paths = with prev; [
            # LSPs
            bash-language-server
            harper
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
            nixfmt
            prettier
            rustfmt
            shfmt
            typstyle
            yamlfmt
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
        # TODO: direnv 2.37.1 test/direnv-test.zsh can hang indefinitely in
        # the Darwin sandbox. Remove when nixpkgs-unstable carries a fixed
        # test suite.
        direnv = prev.direnv.overrideAttrs (_old: {
          doCheck = false;
        });

        # TODO: nushell 0.112.1 SHLVL tests fail in sandbox (Operation not permitted)
        # Fixed in 0.112.2 on master but not yet in nixpkgs-unstable channel.
        # Remove when nixpkgs-unstable advances past e787d9e711e7.
        nushell = prev.nushell.overrideAttrs (old: {
          checkPhase =
            builtins.replaceStrings
              [ "--skip=shell::environment::env::path_is_a_list_in_repl" ]
              [
                "--skip=shell::environment::env::path_is_a_list_in_repl --skip=shell::environment::env::env_shlvl_in_exec_repl --skip=shell::environment::env::env_shlvl_in_repl"
              ]
              old.checkPhase;
        });

        # TODO: ntfy-sh 2.21.0 missing Darwin in serve_unix.go build tags
        # upstream ntfy bug: //go:build excludes darwin. Remove when fixed.
        # ref: https://github.com/NixOS/nixpkgs/issues/493775
        ntfy-sh = prev.ntfy-sh.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace cmd/serve_unix.go \
              --replace-fail \
                '//go:build linux || dragonfly || freebsd || netbsd || openbsd' \
                '//go:build linux || dragonfly || freebsd || netbsd || openbsd || darwin'
          '';
        });
        # Current nixpkgs-unstable has Darwin regressions in dante and in
        # appstream's link flags, which breaks zenity. Pin only the broken
        # Darwin packages to Hydra-cached outputs instead of moving all of
        # nixpkgs to master.
        dante = danteZenityPkgs.dante;
        zenity = danteZenityPkgs.zenity;

        nostr-chat-bar = prev.callPackage ../packages/nostr-chat-bar { };
        systemctl-macos = prev.callPackage ../packages/systemctl { };
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
