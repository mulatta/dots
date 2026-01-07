# Only for NixOS Desktop (Not macOS)
{ pkgs, ... }:
{
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
