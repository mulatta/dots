{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
