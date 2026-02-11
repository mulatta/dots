{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Standalone helix for `nix run` (separate from HM)
      packages.helix = pkgs.callPackage ./helix-standalone.nix {
        inherit (pkgs) helix-lsp-tools;
      };
    };
}
