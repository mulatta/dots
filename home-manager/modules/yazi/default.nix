{
  pkgs,
  lib,
  self,
  ...
}:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) yazi-plugins;
  inherit (self.legacyPackages.${pkgs.stdenv.hostPlatform.system}) yazi-preview-tools;
in
{
  # HM uses regular yazi + preview tools (not standalone)
  # Standalone is for `nix run .#yazi` only
  home.packages = [
    pkgs.yazi
    yazi-preview-tools
  ]
  ++ lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.fontpreview ];

  # Plugins only - config files managed by stow
  xdg.configFile."yazi/plugins".source = "${yazi-plugins}/share/yazi/plugins";
}
