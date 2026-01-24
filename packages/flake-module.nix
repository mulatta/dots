{
  perSystem =
    {
      pkgs,
      inputs',
      ...
    }:
    let
      sieve-sync = pkgs.callPackage ./sieve-sync { };
      jmt = inputs'.jmt.packages.default;
    in
    {
      packages = {
        inherit sieve-sync;
        merge-when-green = pkgs.callPackage ./merge-when-green { inherit jmt; };
        claude-code = pkgs.callPackage ./claude-code {
          claude-code = inputs'.llm-agents.packages.claude-code;
        };
        claude-md = pkgs.callPackage ./claude-md { };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        gh-radicle = pkgs.callPackage ./gh-radicle { };
        email-sync = pkgs.callPackage ./email-sync {
          claude-code = inputs'.llm-agents.packages.claude-code;
        };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
        nextcloud-client = pkgs.callPackage ./nextcloud-client { };
      };
    };
}
