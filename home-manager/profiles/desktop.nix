# Only for NixOS Desktop (Not macOS)
{ pkgs, ... }:
{
  imports = [
    ./base.nix
    ../modules/hyprland
    ../modules/stylix.nix
  ];

  home.packages = [
    pkgs.bitwarden-desktop
  ];
}
