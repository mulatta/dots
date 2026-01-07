# Only for NixOS Desktop (Not macOS)
{ pkgs, ... }:
{
  imports = [
    ../modules/hyprland
    ../modules/stylix.nix
  ];

  home.packages = with pkgs; [
    pkgs.bitwarden-desktop

    mpv
    yt-dlp
    graphicsmagick
  ];
}
