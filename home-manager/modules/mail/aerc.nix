{ pkgs, ... }:
{
  home.packages = [
    pkgs.aerc
    pkgs.mblaze
    pkgs.w3m
  ];
}
