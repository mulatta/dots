{ pkgs, ... }:
{
  programs.bat = {
    enable = true;

    config = {
      style = "numbers,changes";
      italic-text = "always";
      paging = "auto";
      theme = "tokyonight_night";
      map-syntax = [
        "*.json:JSON"
        "*.jsonl:JSON"
        "*.*rc:INI"
        ".*rc:INI"
        "*.conf:INI"
        "*.cfg:INI"
        "~/.config/ghostty/config:Ghostty Config"
      ];
    };

    # delta uses bat's syntax theme set, and home/.gitconfig points it
    # at tokyonight_night. Fetch the upstream tmTheme so the activation
    # `bat cache --build` picks it up.
    themes.tokyonight_night = {
      src = pkgs.fetchFromGitHub {
        owner = "folke";
        repo = "tokyonight.nvim";
        rev = "cdc07ac78467a233fd62c493de29a17e0cf2b2b6";
        hash = "sha256-a9iRWue7DB7s/wNdxqqB51Jya5P9X6sDftqhdmKggU0=";
      };
      file = "extras/sublime/tokyonight_night.tmTheme";
    };

    syntaxes.nextflow = {
      src = pkgs.fetchFromGitHub {
        owner = "peterk87";
        repo = "sublime-nextflow";
        rev = "a7a80779fe90ba49957b9c97241be861214be0ff";
        hash = "sha256-fhvK/gD2cHToSQFmhgbMACwB1+AR+gyCaYwLyCcEsis=";
      };
      file = "Nextflow.sublime-syntax";
    };

    extraPackages = with pkgs.bat-extras; [
      batgrep
      batman
    ];
  };
}
