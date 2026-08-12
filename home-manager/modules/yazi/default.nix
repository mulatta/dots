{
  pkgs,
  lib,
  self,
  ...
}:
let
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  # HM uses regular yazi + preview tools (not standalone)
  # Standalone is for `nix run .#yazi` only
  home.packages =
    with pkgs;
    [
      yazi
      selfPkgs.yazi-preview-tools
    ]
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.fontpreview ];

  # Plugins only - config files managed by stow
  xdg.configFile."yazi/plugins".source = "${selfPkgs.yazi-plugins}/share/yazi/plugins";
}
