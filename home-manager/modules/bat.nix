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

    extraPackages = with pkgs.bat-extras; [
      batgrep
      batman
    ];
  };
}
