{ pkgs, ... }:
{
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      batman
      batgrep
    ];
    config = {
      theme = "Catppuccin Mocha";
      style = "numbers,changes";
      italic-text = "always";
      paging = "auto";
      map-syntax = [
        "*.*rc:INI"
        ".*rc:INI"
        "*.conf:INI"
        "*.cfg:INI"
      ];
    };
  };

  catppuccin.bat.enable = true;
}
