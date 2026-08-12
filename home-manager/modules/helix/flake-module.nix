{ ... }:
{
  perSystem =
    { pkgs, self', ... }:
    {
      # Standalone helix for `nix run` (separate from HM)
      packages.helix = pkgs.callPackage ./helix-standalone.nix {
        inherit (self'.packages) helix-lsp-tools;
      };
    };
}
