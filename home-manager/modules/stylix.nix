{
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
in
{
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    # Nerd Fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.d2coding
    nerd-fonts.symbols-only
    # System fonts
    noto-fonts-cjk-sans
    open-sans
  ];

  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

    targets = {
      firefox = {
        colorTheme.enable = true;
        firefoxGnomeTheme.enable = isLinux;
        profileNames = [ config.home.username ];
      };
      gnome.enable = isLinux;
    };

    fonts = {
      sizes = {
        terminal = 14;
        applications = 12;
        popups = 12;
      };

      serif = {
        name = "Source Serif";
        package = pkgs.source-serif;
      };

      sansSerif = {
        name = "Noto Sans";
        package = pkgs.noto-fonts;
      };

      monospace = {
        package = pkgs.nerd-fonts.d2coding;
        name = "D2Coding";
      };

      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
