{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ../modules/packages.nix
    ../modules/services.nix
    ../modules/fonts.nix
  ];

  xdg.enable = true;

  dconf.enable = lib.mkDefault false;

  home.enableNixpkgsReleaseCheck = false;

  manual.html.enable = false;
  manual.manpages.enable = false;
  manual.json.enable = false;

  home.username = lib.mkDefault "seungwon";
  home.stateVersion = "25.05";
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

  programs.home-manager.enable = true;

  nixpkgs.config.allowUnfree = true;
}
