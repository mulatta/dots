{
  lib,
  buildNpmPackage,
  swiftPackages,
  swift,
}:

let
  targetTriple = "${swift.swiftArch}-apple-macosx14.0";

  webAssets = buildNpmPackage {
    pname = "nostr-chat-bar-web";
    version = "0.1.0";
    # Tests exercise the shared rendering fixture one directory up, so
    # the npm source tree carries Fixtures next to web.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./web
        ./Fixtures
      ];
    };
    sourceRoot = "source/web";
    npmDepsHash = "sha256-xCpTe1lC2BNO1tTuUPeLwvhWHWtfWueFGtfe7QMugT4=";
    npmBuildScript = "build";
    npmFlags = [
      "--ignore-scripts"
      "--loglevel=error"
    ];
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm --loglevel=error test
      npm --loglevel=error run typecheck
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R dist $out/dist
      runHook postInstall
    '';
  };
in
swiftPackages.stdenv.mkDerivation {
  pname = "nostr-chat-bar";
  version = "0.1.0";

  src = ./.;

  MACOSX_DEPLOYMENT_TARGET = "14.0";

  nativeBuildInputs = [ swift ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    export CFFIXED_USER_HOME="$HOME"
    export NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1
    mkdir -p "$HOME"
    swiftc -O -target ${targetTriple} \
      -o nostr-chat-bar \
      Sources/NostrChatBar/*.swift \
      -framework Cocoa \
      -framework Foundation \
      -framework Network \
      -framework UserNotifications \
      -framework WebKit
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/nostr-chat-bar/web
    install -m 755 nostr-chat-bar $out/bin/nostr-chat-bar
    install -m 644 NostrChatBar.icns $out/share/nostr-chat-bar/NostrChatBar.icns
    install -m 644 NoaMenuBarTemplate.png $out/share/nostr-chat-bar/NoaMenuBarTemplate.png
    cp -R ${webAssets}/dist/. $out/share/nostr-chat-bar/web/
    runHook postInstall
  '';

  meta = {
    description = "macOS menubar chat panel for nostr-chatd";
    # Includes licenses from bundled production npm dependencies and fonts.
    license = with lib.licenses; [
      asl20
      bsd2
      bsd3
      isc
      mit
      ofl
      unlicense
    ];
    platforms = lib.platforms.darwin;
    mainProgram = "nostr-chat-bar";
  };
}
