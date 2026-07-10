# Darwin counterpart of noctalia-plugins' nixosModules.nostr-chat.
{
  config,
  pkgs,
  lib,
  self,
  ...
}:

let
  cfg = config.services.nostr-chat;
  plugins = self.inputs.noctalia-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  stateDir = builtins.dirOf cfg.socket;
  barApp = "${config.home.homeDirectory}/Applications/Nostr Chat Bar.app";
  barInfoPlist = pkgs.writeText "nostr-chat-bar-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleDisplayName</key>
      <string>Nostr Chat Bar</string>
      <key>CFBundleExecutable</key>
      <string>nostr-chat-bar</string>
      <key>CFBundleIconFile</key>
      <string>NostrChatBar.icns</string>
      <key>CFBundleIdentifier</key>
      <string>io.mulatta.nostr-chat-bar</string>
      <key>CFBundleName</key>
      <string>Nostr Chat Bar</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>0.1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSUIElement</key>
      <true/>
    </dict>
    </plist>
  '';

  env = {
    NOSTR_CHAT_PEER_PUBKEY = cfg.peerPubkey;
    NOSTR_CHAT_RELAYS = lib.concatStringsSep "," cfg.relays;
    NOSTR_CHAT_DISPLAY_NAME = cfg.displayName;
    NOSTR_CHAT_SECRET_CMD = cfg.secretCommand;
    XDG_CACHE_HOME = config.xdg.cacheHome;
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME = config.xdg.dataHome;
    XDG_STATE_HOME = config.xdg.stateHome;
    PATH = lib.makeBinPath [
      pkgs.rbw
      pkgs.coreutils
    ];
  }
  // lib.optionalAttrs (cfg.blossom != null) {
    NOSTR_CHAT_BLOSSOM = cfg.blossom;
  };
in
{
  options.services.nostr-chat = {
    enable = lib.mkEnableOption "Darwin launchd services for nostr-chatd and nostr-chat-bar";

    package = lib.mkOption {
      type = lib.types.package;
      default = plugins.nostr-chatd;
      description = "nostr-chatd package.";
    };

    barPackage = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.nostr-chat-bar;
      description = "nostr-chat-bar package.";
    };

    peerPubkey = lib.mkOption {
      type = lib.types.str;
      description = "Peer public key in hex form.";
    };

    relays = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Nostr relays used for chat.";
    };

    blossom = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Blossom/NIP-96 media server URL.";
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = config.home.username;
      description = "Display name advertised by nostr-chatd.";
    };

    secretCommand = lib.mkOption {
      type = lib.types.str;
      default = "rbw get nostr-identity";
      description = "Command returning the Nostr secret key.";
    };

    socket = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/nostr-chatd/nostr-chatd.sock";
      description = "Unix socket path shared by daemon and menubar UI.";
    };

    maxHistory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = "Maximum number of messages loaded into the menubar UI.";
    };
  };

  config = lib.mkIf (pkgs.stdenv.isDarwin && cfg.enable) {
    home.packages = [
      cfg.package
      cfg.barPackage
    ];

    home.activation.createNostrChatState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${stateDir}"
      run rm -rf "${barApp}"
      run mkdir -p "${barApp}/Contents/MacOS" "${barApp}/Contents/Resources"
      run install -m 755 "${cfg.barPackage}/bin/nostr-chat-bar" "${barApp}/Contents/MacOS/nostr-chat-bar"
      run install -m 644 "${barInfoPlist}" "${barApp}/Contents/Info.plist"
      run install -m 644 "${cfg.barPackage}/share/nostr-chat-bar/NostrChatBar.icns" "${barApp}/Contents/Resources/NostrChatBar.icns"
      run install -m 644 "${cfg.barPackage}/share/nostr-chat-bar/NoaMenuBarTemplate.png" "${barApp}/Contents/Resources/NoaMenuBarTemplate.png"
      run install -m 644 "${cfg.barPackage}/share/nostr-chat-bar/mermaid.min.js" "${barApp}/Contents/Resources/mermaid.min.js"
      run /usr/bin/codesign --force --deep --sign - "${barApp}"
    '';

    launchd.enable = true;

    launchd.agents.nostr-chatd = {
      enable = true;
      config = {
        ProgramArguments = [
          "${cfg.package}/bin/nostr-chatd"
          "-socket"
          cfg.socket
        ];
        EnvironmentVariables = env;
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${stateDir}/daemon.log";
        StandardErrorPath = "${stateDir}/daemon.log";
      };
    };

    launchd.agents.nostr-chat-bar = {
      enable = true;
      config = {
        ProgramArguments = [
          "${barApp}/Contents/MacOS/nostr-chat-bar"
          "--socket"
          cfg.socket
          "--max-history"
          (toString cfg.maxHistory)
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardOutPath = "${stateDir}/bar.log";
        StandardErrorPath = "${stateDir}/bar.log";
      };
    };
  };
}
