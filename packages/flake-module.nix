{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        spacedrive = pkgs.callPackage ./spacedrive { };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
