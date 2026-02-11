{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Standalone yazi for `nix run` (separate from HM)
      packages.yazi = pkgs.callPackage ./yazi-standalone.nix {
        inherit (pkgs) yazi-plugins yazi-preview-tools;
        yazi = pkgs.yazi;
      };
    };
}
