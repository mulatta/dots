{
  pkgs,
  lib,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  selfPkgs = self.packages.${system};
  aiPkgs = self.inputs.llm-agents.packages.${system};
  kandevRuntime = aiPkgs.kandev.override {
    claudeSupport = true;
    codexSupport = true;
    piSupport = true;
    extraPackages = [
      pkgs.gh
      aiPkgs.prime-agent
    ];
  };
in
{
  imports = [
    ./modules/ai.nix
    ./modules/calendar
    ./modules/chat.nix
    ./modules/darwin-managed-app.nix
    ./modules/docker.nix
    ./modules/keyboard
    ./modules/kubernetes.nix
    ./modules/mail

    ./modules/paneru.nix
    ./modules/zed.nix
    ./modules/zen.nix
    ./modules/zotero.nix
  ];

  home.packages = [
    selfPkgs.instagram-cli
    selfPkgs.openknowledge
    selfPkgs.openknowledge-desktop
    selfPkgs.openlogi
    selfPkgs.radicle-desktop
    pkgs.chatgpt
    aiPkgs.hermes-desktop
    (aiPkgs.kandev-desktop.override {
      inherit kandevRuntime;
    })
    selfPkgs.rbw-pinentry
    (pkgs.yt-dlp.override { ffmpeg-headless = pkgs.ffmpeg; })
    pkgs.basalt
    pkgs.czkawka-full
    pkgs.dorion
    pkgs.tinycast
    pkgs.google-chrome
    pkgs.kanidm_1_11
    pkgs.mpv
    pkgs.obsidian
    pkgs.tailscale
    pkgs.typora
  ];

  programs.rbw.settings = {
    pinentry = lib.mkForce selfPkgs.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
