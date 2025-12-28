{
  lib,
  stdenv,
  fetchurl,
  undmg,
  #linux required
  autoPatchelfHook,
  dpkg,
  gdk-pixbuf,
  glib,
  gst_all_1,
  libsoup_3,
  webkitgtk_4_1,
  xdotool,
}:

let
  pname = "spacedrive";
  version = "2.0.0-alpha.1";

  src =
    fetchurl
      {
        aarch64-darwin = {
          url = "https://github.com/spacedriveapp/spacedrive/releases/download/v${version}/Spacedrive-darwin-aarch64.dmg";
          hash = "sha256-q8Uv8+U7RU4dfKZKv5XBP5F3jHp0u3Mk/PDLdzreJ4U=";
        };
        x86_64-linux = {
          url = "https://github.com/spacedriveapp/spacedrive/releases/download/v${version}/Spacedrive-linux-x86_64.deb";
          hash = "sha256-26qxNO17DTYQSYtH6aRy0PoNpb4BGeoZWOQWZtfV3IY=";
        };
      }
      .${stdenv.system} or (throw "${pname}-${version}: ${stdenv.system} is unsupported.");

  meta = {
    description = "Open source file manager, powered by a virtual distributed filesystem";
    homepage = "https://www.spacedrive.com";
    changelog = "https://github.com/spacedriveapp/spacedrive/releases/tag/v${version}";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    license = lib.licenses.agpl3Plus;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "spacedrive";
  };
in
if stdenv.hostPlatform.isDarwin then
  stdenv.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    sourceRoot = "Spacedrive.app";

    nativeBuildInputs = [ undmg ];

    installPhase = ''
            runHook preInstall

            mkdir -p "$out/Applications/Spacedrive.app"
            cp -r . "$out/Applications/Spacedrive.app"
            mkdir -p "$out/bin"

            # Direct daemon access
            ln -s "$out/Applications/Spacedrive.app/Contents/MacOS/sd-daemon" "$out/bin/sd-daemon"

            # Wrapper script that ensures daemon is running before starting GUI
            # This fixes the race condition where the app times out waiting for daemon
            cat > "$out/bin/spacedrive" <<'WRAPPER'
      #!/bin/bash
      APP_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
      DAEMON="$APP_DIR/Applications/Spacedrive.app/Contents/MacOS/sd-daemon"
      GUI="$APP_DIR/Applications/Spacedrive.app/Contents/MacOS/Spacedrive"
      DATA_DIR="$HOME/Library/Application Support/spacedrive"

      # Check if daemon is already running on port 6969
      if ! lsof -i :6969 >/dev/null 2>&1; then
        # Start daemon in background
        "$DAEMON" --data-dir "$DATA_DIR" &
        # Wait for daemon to be ready (max 10 seconds)
        for i in {1..20}; do
          if lsof -i :6969 >/dev/null 2>&1; then
            break
          fi
          sleep 0.5
        done
      fi

      # Start the GUI
      exec "$GUI" "$@"
      WRAPPER
            chmod +x "$out/bin/spacedrive"

            runHook postInstall
    '';
  }

else
  stdenv.mkDerivation {
    inherit
      pname
      version
      src
      meta
      ;

    nativeBuildInputs = [
      autoPatchelfHook
      dpkg
    ];

    # Depends: libc6, libxdo3, libwebkit2gtk-4.1-0, libgtk-3-0
    # Recommends: gstreamer1.0-plugins-ugly
    # Suggests: gstreamer1.0-plugins-bad
    buildInputs = [
      xdotool
      glib
      libsoup_3
      webkitgtk_4_1
      gdk-pixbuf
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-base
      gst_all_1.gstreamer
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      cp -r usr/share $out/
      cp -r usr/lib $out/
      cp -r usr/bin $out/

      runHook postInstall
    '';
  }
