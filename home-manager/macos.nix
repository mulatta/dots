{
  config,
  pkgs,
  lib,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  selfPkgs = self.packages.${system};
  aiPkgs = self.inputs.llm-agents.packages.${system};
  secretiveSocket = "${config.home.homeDirectory}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
  kandevRuntimeBase = aiPkgs.kandev.override {
    claudeSupport = true;
    codexSupport = true;
    piSupport = true;
    extraPackages = [
      pkgs.gh
      aiPkgs.prime-agent
    ];
  };
  kandevRuntime = kandevRuntimeBase.overrideAttrs (old: {
    passthru = old.passthru // {
      agentRuntimeEnvironment = old.passthru.agentRuntimeEnvironment // {
        SSH_AUTH_SOCK = secretiveSocket;
      };
      agentRuntimeWrapperArgs = old.passthru.agentRuntimeWrapperArgs ++ [
        "--set"
        "SSH_AUTH_SOCK"
        secretiveSocket
      ];
    };
  });
in
{
  imports = [
    ./modules/calendar
    ./modules/chat.nix
    ./modules/docker.nix
    ./modules/herdr/open-file.nix
    ./modules/keyboard
    ./modules/llm-agents
    ./modules/mail
    ./modules/nostr-chat.nix
    ./modules/ntfy.nix
    ./modules/paneru.nix
    ./modules/zen.nix
    ./modules/zotero.nix
  ];

  home.packages = [
    selfPkgs.instagram-cli
    selfPkgs.openlogi
    selfPkgs.radicle-desktop
    aiPkgs.hermes-desktop
    (aiPkgs.kandev-desktop.override {
      inherit kandevRuntime;
    })
    selfPkgs.rbw-pinentry
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
    pinentry = lib.mkForce selfPkgs.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
