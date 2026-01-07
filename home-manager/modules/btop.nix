{ lib, ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      vim_keys = true;
      color_theme = lib.mkForce "horizon";
    };
  };
}
