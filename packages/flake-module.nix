{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        spacedrive = pkgs.callPackage ./spacedrive { };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
