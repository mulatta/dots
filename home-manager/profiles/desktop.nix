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
    ../modules/zen.nix
  ];

  home.packages =
    (with pkgs; [
      bitwarden-desktop
      graphicsmagick
      mpv
      yt-dlp
      zotero
    ])
    ++ [
      self.packages.${system}.instagram-cli
      self.packages.${system}.radicle-desktop
      self.packages.${system}.rbw-pinentry
    ];
}
