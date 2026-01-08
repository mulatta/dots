# Only for NixOS Desktop (Not macOS)
{ config, pkgs, ... }:
{
  dconf.enable = true;

  imports = [
    ../modules/mail
    ../modules/thunderbird.nix
  ];

  # NixOS desktop stylix targets
  stylix.targets = {
    gnome.enable = true;
    gtk.enable = true;
    firefox = {
      enable = true;
      colorTheme.enable = true;
      firefoxGnomeTheme.enable = true;
      profileNames = [ config.home.username ];
    };
  };

  home.packages = with pkgs; [
    bitwarden-desktop
    mpv
    yt-dlp
    graphicsmagick
  ];
}
