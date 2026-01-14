{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.d2coding
    nerd-fonts.symbols-only
    noto-fonts-cjk-sans
    open-sans
    source-serif
    noto-fonts
    noto-fonts-color-emoji
  ];
}
