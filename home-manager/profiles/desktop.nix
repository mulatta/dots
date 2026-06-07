{
  pkgs,
  lib,
  self,
  system,
  ...
}:
{
  dconf.enable = true;

  # bitwarden-desktop 2026.5.0 still pins electron_39 (39.8.10), which nixpkgs
  # marks EOL. Upstream has not bumped it yet; allow until it moves to a
  # supported electron.
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

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
      self.packages.${system}.rbw-pinentry
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      self.packages.${system}.radicle-desktop
    ];

  programs.rbw.settings = {
    pinentry = lib.mkForce self.packages.${system}.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
