# Only for NixOS Desktop (Not macOS)
{ pkgs, ... }:
{
  dconf.enable = true;

  imports = [
    ../modules/mail
    ../modules/stylix.nix
    ../modules/thunderbird.nix
  ];

  home.packages = with pkgs; [
    pkgs.bitwarden-desktop

    mpv
    yt-dlp
    graphicsmagick
  ];
}
