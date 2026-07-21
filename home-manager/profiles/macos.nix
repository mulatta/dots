{
  pkgs,
  lib,
  self,
  system,
  ...
}:
{
  imports = [
    ../modules/calendar
    ../modules/keyboard
    ../modules/llm-agents
    ../modules/mail
    ../modules/nostr-chat.nix
    ../modules/ntfy.nix
    ../modules/paneru.nix
    ../modules/tmux-open-file.nix
    ../modules/zen.nix
    ../modules/zotero.nix
  ];

  home.packages =
    let
      myPkgs = self.packages.${system};
    in
    [
      myPkgs.instagram-cli
      myPkgs.jj-forklift
      myPkgs.radicle-desktop
      myPkgs.rbw-pinentry
      (pkgs.yt-dlp.override { ffmpeg-headless = pkgs.ffmpeg; })
      pkgs.basalt
      pkgs.czkawka-full
      pkgs.dorion
      pkgs.google-chrome
      pkgs.mpv
      pkgs.obsidian
      pkgs.tailscale
      pkgs.typora
    ];

  services.nostr-chat = {
    enable = true;
    peerPubkey = lib.strings.trim (
      builtins.readFile "${self}/vars/per-machine/malt/opencrow/nostr-public-key/value"
    );
    relays = [
      "wss://relay.mulatta.io"
      "wss://relay.primal.net"
      "wss://nos.lol"
    ];
    blossom = "https://blossom.mulatta.io";
    displayName = "Noa";
    secretCommand = "rbw get nostr-identity";
  };

  programs.rbw.settings = {
    pinentry = lib.mkForce self.packages.${system}.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
