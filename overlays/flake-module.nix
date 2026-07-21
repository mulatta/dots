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
      in
      {
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

        # libfyaml's Darwin pkg-config file can contain literal configure text.
        # Meson passes those words to clang when linking appstream.
        libfyaml = prev.libfyaml.overrideAttrs (
          old:
          lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
            postInstall = (old.postInstall or "") + ''
              substituteInPlace "$dev/lib/pkgconfig/libfyaml.pc" \
                --replace-fail "none required" ""
            '';
          }
        );

        # rust-s3 0.35 signs empty body headers on ranged GET and DELETE.
        # Cloudflare R2 rejects those signatures, breaking JMAP attachment
        # downloads and blob garbage collection. Keep this until rust-s3 merges
        # PRs #459/#465 and Stalwart bumps the crate.
        stalwart = prev.stalwart_0_15.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../packages/stalwart/return-empty-s3-blob-for-empty-range.patch
          ];

          cargoDeps =
            let
              rust-s3-r2-range-get-signing-fix = prev.fetchpatch {
                url = "https://github.com/durch/rust-s3/commit/4c7ed2b44d6fbf1ebdd401dd3a81c14d288cffb2.patch";
                relative = "s3";
                hash = "sha256-f4OBtd/XcERHSckluRh2ESTumygIMnEv7GMqPXT18QQ=";
              };
            in
            prev.runCommand "${old.pname}-${old.version}-vendor-rust-s3-r2-signing-fixes" { } ''
              cp -R ${old.cargoDeps} "$out"
              chmod -R u+w "$out/source-registry-0/rust-s3-0.35.1"
              cd "$out/source-registry-0/rust-s3-0.35.1"
              patch -p1 < ${rust-s3-r2-range-get-signing-fix}
              patch -p1 < ${../packages/stalwart/rust-s3-skip-delete-object-body-headers.patch}
              grep -F 'Command::GetObjectRange { .. } => {}' src/request/request_trait.rs
              grep -F 'Command::DeleteObject => {}' src/request/request_trait.rs
            '';
        });

        # Custom packages
        archify-cli = prev.callPackage ../packages/archify { };
        rsshub = prev.callPackage ../packages/rsshub {
          rsshub = prev.rsshub;
        };
        bulwark-webmail = prev.callPackage ../packages/bulwark-webmail { };
        merge-when-green = prev.callPackage ../packages/merge-when-green {
          flake-fmt = inputs.flake-fmt.packages.${system}.default;
        };
        claude-md = prev.callPackage ../packages/claude-md { };
        rbw-pinentry = prev.callPackage ../packages/rbw-pinentry { };
        rhwp = inputs.rhwp.packages.${system}.rhwp-cli;
        email-sync = prev.callPackage ../packages/email-sync { };
        msmtp-with-sent = prev.callPackage ../packages/msmtp-with-sent { };
        n8n-hooks = prev.callPackage ../packages/n8n-hooks { };
        jellyfin-plugin-sso-auth = prev.callPackage ../packages/jellyfin-plugin-sso-auth { };
        miniflux-sync = prev.callPackage ../packages/miniflux-sync { };
        ntfy-subscribe = prev.callPackage ../packages/ntfy-subscribe { };
        pim = prev.callPackage ../packages/pim {
          calendar-cli = inputs.skillz.packages.${system}.calendar-cli.override {
            msmtp = final.msmtp-with-sent;
          };
          crabfit-cli = inputs.skillz.packages.${system}.crabfit-cli;
          nodePath = "${prev.callPackage ../home/.pi/agent/default.nix { }}/node_modules";
          miniflux-cli = inputs.skillz.packages.${system}.miniflux-cli;
          vikunja-cli = inputs.skillz.packages.${system}.vikunja-cli;
          biorefs-cli = inputs.skillz.packages.${system}.biorefs-cli;
          pymol-cli = inputs.skillz.packages.${system}.pymol-cli;
          n8n-hooks = final.n8n-hooks;
          pi = inputs.llm-agents.packages.${system}.pi;
        };
        updater = prev.callPackage ../packages/updater { };
        jj-forklift = prev.callPackage ../packages/jj-forklift { };
        instagram-cli = prev.callPackage ../packages/instagram-cli { };
        instant-deploy = prev.callPackage ../packages/instant-deploy {
          clan-cli = inputs.clan-core.packages.${system}.clan-cli;
        };
        radicle-desktop = prev.callPackage ../packages/radicle-desktop { };

        # Tool bundles consumed by the helix/yazi modules.
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
        nostr-chat-bar = prev.callPackage ../packages/nostr-chat-bar { };
        systemctl-macos = prev.callPackage ../packages/systemctl { };
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
