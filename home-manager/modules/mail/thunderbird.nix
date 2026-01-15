# Thunderbird - accounts configured manually (not via home-manager)
{ pkgs, ... }:
{
  home.packages = [ pkgs.thunderbird ];
}
