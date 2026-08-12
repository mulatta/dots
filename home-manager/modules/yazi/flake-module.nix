{ ... }:
{
  perSystem =
    { pkgs, self', ... }:
    {
      # Standalone yazi for `nix run` (separate from HM)
      packages.yazi = pkgs.callPackage ./yazi-standalone.nix {
        inherit (self'.packages) yazi-plugins yazi-preview-tools;
        yazi = pkgs.yazi;
      };
    };
}
