{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.helix = pkgs.callPackage ./helix-standalone.nix { };
    };
}
