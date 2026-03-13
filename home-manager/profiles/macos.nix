{
  pkgs,
  self,
  system,
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
      myPkgs.radicle-desktop
      myPkgs.rbw-pinentry
      myPkgs.meetily
      myPkgs.instagram-cli
      pkgs.mpv
      pkgs.yt-dlp
      pkgs.tailscale
      pkgs.basalt
      pkgs.obsidian
      # pkgs.zotero
    ];
}
