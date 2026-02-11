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
      mpv
      yt-dlp
      graphicsmagick
      zotero
    ])
    ++ [
      self.packages.${system}.radicle-desktop
      self.packages.${system}.rbw-pinentry
      self.packages.${system}.instagram-cli
    ];
}
