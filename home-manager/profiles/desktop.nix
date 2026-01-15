{ pkgs, ... }:
{
  dconf.enable = true;

  imports = [
    ../modules/calendar
    ../modules/mail
  ];

  home.packages = with pkgs; [
    bitwarden-desktop
    mpv
    yt-dlp
    graphicsmagick
  ];
}
