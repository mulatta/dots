{ pkgs, ... }:
{
  programs.zellij = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      default_mode = "normal";
      default_shell = "${pkgs.fish}/bin/fish";
      theme = "catppuccin-macha";
    };
  };
}
