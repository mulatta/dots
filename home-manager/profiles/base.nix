{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ../modules/atuin.nix
    ../modules/fonts.nix
    ../modules/helix
    ../modules/packages.nix
    ../modules/yazi
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

  nix.package = pkgs.nixVersions.latest;

  home.packages = [
    config.nix.package
  ];

  home.sessionVariables = {
    LC_COLLATE = "C.UTF-8";
    NIKS3_SERVER_URL = "https://niks3.mulatta.io";
  };
}
