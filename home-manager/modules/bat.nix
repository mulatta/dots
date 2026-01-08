{ pkgs, ... }:
{
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      batman
      batgrep
    ];
    config = {
      style = "numbers,changes";
      italic-text = "always";
      paging = "auto";
      map-syntax = [
        "*.json:JSON"
        "*.jsonl:JSON"
        "*.*rc:INI"
        ".*rc:INI"
        "*.conf:INI"
        "*.cfg:INI"
      ];
    };
  };
}
