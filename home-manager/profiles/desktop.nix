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
    ../modules/keyboard
    ../modules/mail
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
      self.packages.${system}.rbw-pinentry
    ];
}
