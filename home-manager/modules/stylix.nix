{
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
in
{
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    nerd-fonts.symbols-only
    open-sans
    # wallpapers
  ];

  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

    # iconTheme = {
    #   enable = true;
    #   # Linux Only pkgs
    #   package = pkgs.catppuccin-papirus-folders.override {
    #     flavor = "mocha";
    #     accent = "lavender";
    #   };
    #   dark = "Papirus-Dark";
    # };

    targets = {
      firefox = {
        colorTheme.enable = true;
        firefoxGnomeTheme.enable = !isDarwin;
        profileNames = [ config.home.username ];
      };
      gnome.enable = !isDarwin;
    };

    # image = pkgs.wallpapers.windows-error;

    # cursor = {
    #   name = "Bibata-Modern-Classic";
    #   package = pkgs.bibata-cursors;
    #   size = 24;
    # };

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
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
