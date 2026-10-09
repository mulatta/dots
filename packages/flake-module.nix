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
      skillz = inputs'.skillz.packages;
    in
    {
      packages = {
        archify-cli = pkgs.callPackage ./archify-cli { };
        browser-harness = pkgs.callPackage ./browser-harness {
          inherit (llmAgents) versionCheckHomeHook;
        };
        browser-use = pkgs.callPackage ./browser-use {
          inherit (self'.packages) browser-harness;
        };
        bulwark-webmail = pkgs.callPackage ./bulwark-webmail { };
        buzz-agents-sync = pkgs.callPackage ./buzz-agents-sync {
          buzz-cli = inputs'.buzz.packages.buzz-cli;
          clan-cli = inputs'.clan-core.packages.clan-cli;
        };
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
        maiao = pkgs.callPackage ./maiao { };
        merge-when-green = pkgs.callPackage ./merge-when-green {
          flake-fmt = inputs'.flake-fmt.packages.default;
        };
        miniflux-sync = pkgs.callPackage ./miniflux-sync { };
        msmtp-with-sent = pkgs.callPackage ./msmtp-with-sent { };
        nextflow-language-server = pkgs.callPackage ./nextflow-language-server { };
        openknowledge = pkgs.callPackage ./openknowledge { };
        openknowledge-desktop = self'.packages.openknowledge.desktop;
        pi-acp = pkgs.callPackage ./pi-acp {
          pi = llmAgents.pi;
        };
        pim = pkgs.callPackage ./pim {
          inherit (self'.packages) email-sync msmtp-with-sent;
          calendar-cli = skillz.calendar-cli.override {
            msmtp = self'.packages.msmtp-with-sent;
          };
          crabfit-cli = skillz.crabfit-cli;
          miniflux-cli = skillz.miniflux-cli;
          biorefs-cli = skillz.biorefs-cli;
          pi = llmAgents.pi;
        };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        rhwp = inputs'.rhwp.packages.rhwp-cli;
        rsshub = pkgs.callPackage ./rsshub {
          rsshub = pkgs.rsshub;
        };
        termaid = pkgs.callPackage ./termaid { };
        trek = pkgs.callPackage ./trek { };
        tree-sitter-nextflow = pkgs.callPackage ./tree-sitter-nextflow { };
        updater = pkgs.callPackage ./updater { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        openlogi = pkgs.callPackage ./openlogi { };
        radicle-desktop = pkgs.callPackage ./radicle-desktop { };
        systemctl-macos = pkgs.callPackage ./systemctl { };
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        neko-image = pkgs.callPackage ./neko-image { };
      };
    };
}
