{
  pkgs,
  lib,
  ...
}:
{
  # HM uses regular yazi + preview tools (not standalone)
  # Standalone is for `nix run .#yazi` only
  home.packages =
    with pkgs;
    [
      yazi
      yazi-preview-tools
    ]
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.fontpreview ];

  # Plugins only - config files managed by stow
  xdg.configFile."yazi/plugins".source = "${pkgs.yazi-plugins}/share/yazi/plugins";
}
