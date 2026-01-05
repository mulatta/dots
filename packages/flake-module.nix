{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      jmt = pkgs.callPackage ./jmt { };
    in
    {
      packages = {
        inherit jmt;
        merge-when-green = pkgs.callPackage ./merge-when-green { inherit jmt; };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
        gh-radicle = pkgs.callPackage ./gh-radicle { };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
