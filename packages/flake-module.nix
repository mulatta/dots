{
  perSystem =
    {
      pkgs,
      lib,
      inputs',
      ...
    }:
    let
      aiPkgs = inputs'.llm-agents.packages;
    in
    {
      packages = {
        archify-cli = pkgs.callPackage ./archify-cli { };
        claude-code = pkgs.callPackage ./claude-code {
          claude-code = aiPkgs.claude-code;
        };
        claude-md = pkgs.callPackage ./claude-md { };
        email-sync = pkgs.callPackage ./email-sync { };

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
        # Paperless's interpreter, so the entry point loads there.
        paperless-rhwp = pkgs.paperless-ngx.python.pkgs.callPackage ./paperless-rhwp {
          rhwp = inputs'.rhwp.packages.rhwp-cli;
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
