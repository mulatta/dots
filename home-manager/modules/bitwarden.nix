{ lib, pkgs, ... }:
{
  programs.rbw = {
    enable = true;
    settings = {
      email = lib.mkDefault "seungwon@mulatta.io";
      base_url = "https://vaultwarden.mulatta.io";
      pinentry = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-curses;
    };
  };
}
