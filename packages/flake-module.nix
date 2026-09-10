{
  perSystem =
    {
      pkgs,
      lib,
      inputs',
      self',
      ...
    }:
    let
      llmAgents = inputs'.llm-agents.packages;
      researchSkills = inputs'.research-skills.packages;
      skillz = inputs'.skillz.packages;
    in
    {
      packages = {
        archify-cli = pkgs.callPackage ./archify { };
        bulwark-webmail = pkgs.callPackage ./bulwark-webmail { };
        claude-code = pkgs.callPackage ./claude-code {
          claude-code = llmAgents.claude-code;
        };
        claude-md = pkgs.callPackage ./claude-md { };
        email-sync = pkgs.callPackage ./email-sync { };

        herdr-autoname = pkgs.callPackage ./herdr-autoname { };
        herdr-sesh = pkgs.callPackage ./herdr-sesh { };
        instagram-cli = pkgs.callPackage ./instagram-cli { };
        jellyfin-plugin-sso-auth = pkgs.callPackage ./jellyfin-plugin-sso-auth { };
        loc = pkgs.callPackage ./loc { };
        merge-when-green = pkgs.callPackage ./merge-when-green {
          flake-fmt = inputs'.flake-fmt.packages.default;
        };
        miniflux-sync = pkgs.callPackage ./miniflux-sync { };
        msmtp-with-sent = pkgs.callPackage ./msmtp-with-sent { };
        n8n-hooks = pkgs.callPackage ./n8n-hooks { };
        ntfy-subscribe = pkgs.callPackage ./ntfy-subscribe { };
        pim = pkgs.callPackage ./pim {
          inherit (self'.packages) n8n-hooks email-sync msmtp-with-sent;
          calendar-cli = skillz.calendar-cli.override {
            msmtp = self'.packages.msmtp-with-sent;
          };
          crabfit-cli = skillz.crabfit-cli;
          miniflux-cli = skillz.miniflux-cli;
          biorefs-cli = skillz.biorefs-cli;
          pymol-cli = researchSkills.pymol-cli;
          pi = llmAgents.pi;
        };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        rhwp = inputs'.rhwp.packages.rhwp-cli;
        rsshub = pkgs.callPackage ./rsshub {
          rsshub = pkgs.rsshub;
        };
        updater = pkgs.callPackage ./updater { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        nostr-chat-bar = pkgs.callPackage ./nostr-chat-bar { };
        openlogi = pkgs.callPackage ./openlogi { };
        paneru-app = pkgs.callPackage ./paneru-app {
          paneru = inputs'.paneru.packages.default;
        };
        radicle-desktop = pkgs.callPackage ./radicle-desktop { };
        systemctl-macos = pkgs.callPackage ./systemctl { };
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        neko-image = pkgs.callPackage ./neko-image { };
      };
    };
}
