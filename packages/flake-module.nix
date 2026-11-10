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
      aiPkgs = inputs'.llm-agents.packages;
      skillz = inputs'.skillz.packages;
    in
    {
      packages = {
        archify-cli = pkgs.callPackage ./archify-cli { };
        claude-code = pkgs.callPackage ./claude-code {
          claude-code = aiPkgs.claude-code;
        };
        claude-md = pkgs.callPackage ./claude-md { };
        # nixpkgs' aws-lc now prefixes its symbols and no longer ships the
        # openssl.pc that codex's openssl-sys found, so link OpenSSL itself.
        # Drop once llm-agents.nix builds against a nixpkgs with that aws-lc.
        codex = aiPkgs.codex.overrideAttrs (old: {
          buildInputs = old.buildInputs ++ [ pkgs.openssl ];
        });
        codex-acp = aiPkgs.codex-acp.override { inherit (self'.packages) codex; };
        email-sync = pkgs.callPackage ./email-sync { };

        herdr-autoname = pkgs.callPackage ./herdr-autoname { };
        herdr-sesh = pkgs.callPackage ./herdr-sesh { };
        hindsight-client = pkgs.python3Packages.callPackage ./hindsight-client {
          inherit (aiPkgs) hindsight;
        };
        hindsight-plugins = pkgs.callPackage ./hindsight-plugins { inherit (aiPkgs) hindsight; };
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
        openknowledge = pkgs.callPackage ./openknowledge {
          inherit (aiPkgs)
            pi
            pi-acp
            claude-code
            claude-agent-acp
            ;
          inherit (self'.packages) codex codex-acp;
          piSupport = true;
          claudeSupport = true;
          codexSupport = true;
        };
        openknowledge-desktop = self'.packages.openknowledge.desktop;
        # Paperless's interpreter, so the entry point loads there.
        paperless-rhwp = pkgs.paperless-ngx.python.pkgs.callPackage ./paperless-rhwp {
          rhwp = inputs'.rhwp.packages.rhwp-cli;
        };
        pim = pkgs.callPackage ./pim {
          inherit (self'.packages) email-sync msmtp-with-sent;
          calendar-cli = skillz.calendar-cli.override {
            msmtp = self'.packages.msmtp-with-sent;
          };
          crabfit-cli = skillz.crabfit-cli;
          miniflux-cli = skillz.miniflux-cli;
          biorefs-cli = skillz.biorefs-cli;
          pi = aiPkgs.pi;
        };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        rhwp = inputs'.rhwp.packages.rhwp-cli;
        rsshub = pkgs.callPackage ./rsshub {
          rsshub = pkgs.rsshub;
        };
        trek = pkgs.callPackage ./trek { };
        tree-sitter-nextflow = pkgs.callPackage ./tree-sitter-nextflow { };
        updater = pkgs.callPackage ./updater { };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        openlogi = pkgs.callPackage ./openlogi { };
        radicle-desktop = pkgs.callPackage ./radicle-desktop { };
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
