{
  self,
  system,
  pkgs,
  ...
}:
{
  imports = [
    ../modules/calendar
    ../modules/keyboard
    ../modules/llm-agents.nix
    ../modules/mail
    ../modules/zen.nix
    ../modules/ntfy.nix
  ];

  home.packages =
    let
      myPkgs = self.packages.${system};
    in
    [
      myPkgs.nextcloud-client
      myPkgs.radicle-desktop
      myPkgs.rbw-pinentry
      myPkgs.meetily
      pkgs.mpv
      pkgs.yt-dlp
      pkgs.tailscale
      pkgs.basalt
    ];
}
