{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./yazi.toml);
    keymap = builtins.fromTOML (builtins.readFile ./keymap.toml);
    theme = import ./theme.nix;
    flavors = import ./flavors.nix { inherit pkgs; };
    plugins = import ./plugins.nix { inherit pkgs; };
    shellWrapperName = "y";
  };

  home.packages =
    with pkgs;
    [
      imagemagick
      ffmpegthumbnailer
      unar
      poppler
      unar
    ]
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [ fontpreview ];
}
