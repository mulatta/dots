{
  pkgs,
  self,
  system,
  ...
}:
{
  dconf.enable = true;

  imports = [
    ../modules/calendar
    ../modules/mail
    ../modules/keyboard
  ];

  home.packages =
    (with pkgs; [
      bitwarden-desktop
      mpv
      yt-dlp
      graphicsmagick
    ])
    ++ [
      self.packages.${system}.radicle-desktop
    ];
}
