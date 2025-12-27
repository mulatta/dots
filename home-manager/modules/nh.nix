{ config, ... }:
{
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/dots";
    clean = {
      enable = true;
      dates = "monthly";
      extraArgs = "--keep 5 --keep-since 1m";
    };
  };
}
