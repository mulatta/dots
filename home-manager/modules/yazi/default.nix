{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    plugins = import ./plugins.nix { inherit pkgs; };
    shellWrapperName = "y";
  };
}
