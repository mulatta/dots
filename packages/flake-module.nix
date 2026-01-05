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
        spacedrive = pkgs.callPackage ./spacedrive { };
        rbw-pinentry = pkgs.callPackage ./rbw-pinentry { };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        systemctl-macos = pkgs.callPackage ./systemctl { };
      };
    };
}
