{ pkgs, ... }:
{
  dconf.enable = true;

  imports = [
    ../modules/calendar
    ../modules/mail
    ../modules/thunderbird.nix
  ];

  home.packages = with pkgs; [
    bitwarden-desktop
    mpv
    yt-dlp
    graphicsmagick
  ];
}
