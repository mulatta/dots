{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      inputs',
      self',
      ...
    }:
    let
      skillz = inputs'.skillz.packages;
      llmAgents = inputs'.llm-agents.packages;
      packages = {
        claude-code = pkgs.callPackage ../packages/claude-code {
          claude-code = llmAgents.claude-code;
        };
        archify-cli = pkgs.callPackage ../packages/archify { };
        rsshub = pkgs.callPackage ../packages/rsshub {
          rsshub = pkgs.rsshub;
        };
        bulwark-webmail = pkgs.callPackage ../packages/bulwark-webmail { };
        merge-when-green = pkgs.callPackage ../packages/merge-when-green {
          flake-fmt = inputs'.flake-fmt.packages.default;
        };
        claude-md = pkgs.callPackage ../packages/claude-md { };
        rbw-pinentry = pkgs.callPackage ../packages/rbw-pinentry { };
        rhwp = inputs'.rhwp.packages.rhwp-cli;
        email-sync = pkgs.callPackage ../packages/email-sync { };
        msmtp-with-sent = pkgs.callPackage ../packages/msmtp-with-sent { };
        n8n-hooks = pkgs.callPackage ../packages/n8n-hooks { };
        jellyfin-plugin-sso-auth = pkgs.callPackage ../packages/jellyfin-plugin-sso-auth { };
        miniflux-sync = pkgs.callPackage ../packages/miniflux-sync { };
        ntfy-subscribe = pkgs.callPackage ../packages/ntfy-subscribe { };
        pim = pkgs.callPackage ../packages/pim {
          inherit (self'.packages) n8n-hooks email-sync msmtp-with-sent;
          calendar-cli = skillz.calendar-cli.override {
            msmtp = self'.packages.msmtp-with-sent;
          };
          crabfit-cli = skillz.crabfit-cli;
          miniflux-cli = skillz.miniflux-cli;
          vikunja-cli = skillz.vikunja-cli;
          biorefs-cli = skillz.biorefs-cli;
          pymol-cli = skillz.pymol-cli;
          pi = llmAgents.pi;
        };
        updater = pkgs.callPackage ../packages/updater { };
        instagram-cli = pkgs.callPackage ../packages/instagram-cli { };
        loc = pkgs.callPackage ../packages/loc { };

        helix-lsp-tools = pkgs.buildEnv {
          name = "helix-lsp-tools";
          paths = with pkgs; [
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
            plugins = with pkgs.yaziPlugins; {
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
          pkgs.runCommand "yazi-plugins" { } ''
            mkdir -p $out/share/yazi/plugins
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: pkg: ''
                ln -s ${pkg} $out/share/yazi/plugins/${name}.yazi
              '') plugins
            )}
          '';

        yazi-preview-tools = pkgs.buildEnv {
          name = "yazi-preview-tools";
          paths = with pkgs; [
            imagemagick
            ffmpegthumbnailer
            unar
            poppler
            glow
          ];
        };

        herdr-sesh = pkgs.callPackage ./herdr-sesh { };
        herdr-autoname = pkgs.callPackage ./herdr-autoname { };
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        neko-image = pkgs.callPackage ./neko-image { };
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        nostr-chat-bar = pkgs.callPackage ../packages/nostr-chat-bar { };
        paneru-app = pkgs.callPackage ../packages/paneru-app {
          paneru = inputs'.paneru.packages.default;
        };
        openlogi = pkgs.callPackage ../packages/openlogi { };
        radicle-desktop = pkgs.callPackage ../packages/radicle-desktop { };
        systemctl-macos = pkgs.callPackage ../packages/systemctl { };
      };
    in
    {
      inherit packages;
    };
}
