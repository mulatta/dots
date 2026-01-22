{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      jmt = inputs.jmt.packages.${system}.default;
      sieve-sync = pkgs.callPackage ./sieve-sync { };
    in
    {
      packages = {
        inherit jmt sieve-sync;
        merge-when-green = pkgs.callPackage ./merge-when-green { inherit jmt; };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        gh-radicle = pkgs.callPackage ./gh-radicle { };
        aerc-empty-trash = pkgs.callPackage ./aerc-empty-trash { };
        email-sync = pkgs.callPackage ./email-sync {
          claude-code = inputs.llm-agents.packages.${system}.claude-code;
        };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
        nextcloud-client = pkgs.callPackage ./nextcloud-client { };
      };
    };
}
