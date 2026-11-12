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

  # Grab disables macOS hotkeys and the menu drops Cmd+Q/H/W/M, so they reach GNOME.
  sdl3 = pkgs.sdl3.overrideAttrs (old: {
    env.NIX_CFLAGS_COMPILE = "-DSDL_MAC_NO_SANDBOX";
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/video/cocoa/SDL_cocoaevents.m \
        --replace-fail 'keyEquivalent:@"q"' 'keyEquivalent:@""' \
        --replace-fail 'keyEquivalent:@"h"' 'keyEquivalent:@""' \
        --replace-fail 'keyEquivalent:@"w"' 'keyEquivalent:@""' \
        --replace-fail 'keyEquivalent:@"m"' 'keyEquivalent:@""' \
        --replace-fail 'keyEquivalent:@","' 'keyEquivalent:@""' \
        --replace-fail 'keyEquivalent:@"f"' 'keyEquivalent:@""'
    '';
  });
  freerdpGrab = pkgs.freerdp.override {
    inherit sdl3;
    sdl3-ttf = pkgs.sdl3-ttf.override { inherit sdl3; };
    sdl3-image = pkgs.sdl3-image.override { inherit sdl3; };
  };

  # Args go through stdin so the RDP password stays out of argv.
  citraDesktopBin = pkgs.writeShellApplication {
    name = "citra-desktop";
    # Finder launches the app with a bare PATH.
    runtimeInputs = [
      freerdpGrab
      pkgs.netcat
      config.programs.rbw.package
    ];
    text = ''
      host=10.208.0.10
      # Naru is direct at home; fall back to WireGuard when its path is down.
      nc -z -w 2 "$host" 3389 2>/dev/null || host="[fd28:387a:8e:7600:f53d:6c67:5495:67eb]"
      password=$(rbw get citra-rdp)
      printf '%s\n' "/v:$host" /u:seungwon "/p:$password" /cert:tofu /dynamic-resolution \
        | sdl-freerdp /args-from:stdin
    '';
  };
  citraDesktop = pkgs.runCommand "citra-desktop" { } ''
    mkdir -p $out/bin "$out/Applications/Citra Desktop.app/Contents/MacOS"
    ln -s ${citraDesktopBin}/bin/citra-desktop $out/bin/citra-desktop
    cat > "$out/Applications/Citra Desktop.app/Contents/Info.plist" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>citra-desktop</string>
      <key>CFBundleIdentifier</key><string>io.mulatta.citra-desktop</string>
      <key>CFBundleName</key><string>Citra Desktop</string>
      <key>CFBundlePackageType</key><string>APPL</string>
    </dict></plist>
    EOF
    cat > "$out/Applications/Citra Desktop.app/Contents/MacOS/citra-desktop" <<EOF
    #!/bin/sh
    exec ${citraDesktopBin}/bin/citra-desktop >>"\$HOME/Library/Logs/citra-desktop.log" 2>&1
    EOF
    chmod +x "$out/Applications/Citra Desktop.app/Contents/MacOS/citra-desktop"
  '';
in
{
  imports = [
    ./modules/ai.nix
    ./modules/calendar
    ./modules/chat.nix
    ./modules/darwin-apps
    ./modules/docker.nix
    ./modules/keyboard
    ./modules/kubernetes.nix
    ./modules/mail

    ./modules/paneru.nix
    ./modules/zen.nix
    ./modules/zotero.nix
  ];

  home.packages = [
    selfPkgs.instagram-cli
    selfPkgs.openlogi
    selfPkgs.radicle-desktop
    pkgs.chatgpt
    aiPkgs.hermes-desktop
    aiPkgs.herdr-app
    selfPkgs.rbw-pinentry
    (pkgs.yt-dlp.override { ffmpeg-headless = pkgs.ffmpeg; })
    pkgs.basalt
    pkgs.czkawka-full
    pkgs.tinycast
    pkgs.google-chrome
    pkgs.kanidm_1_11
    pkgs.mpv
    pkgs.obsidian
    pkgs.tailscale
    pkgs.typora
    citraDesktop
  ];

  # Public half of the login keychain identity from code-signing-identity.
  targets.darwin.codeSigning.certificateSha1 = "d5f52c1ea9644923482d539ccfc51dc51c920080";

  programs.rbw.settings = {
    pinentry = lib.mkForce selfPkgs.rbw-pinentry;
    lock_timeout = lib.mkForce 3600;
  };
}
