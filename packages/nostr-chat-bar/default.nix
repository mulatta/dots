{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  swiftPackages,
  swift,
}:

let
  swift-markdown = fetchFromGitHub {
    owner = "swiftlang";
    repo = "swift-markdown";
    rev = "0.6.0";
    hash = "sha256-03iJLuigQM6bKyHwbmmYW07UWInqKSiLx8Zj/9MLhfo=";
  };
  swift-cmark = fetchFromGitHub {
    owner = "swiftlang";
    repo = "swift-cmark";
    rev = "924936d0427cb25a61169739a7660230bffa6ea6";
    hash = "sha256-0pyZ5yQRsbiKwz2XT8N6dMwCLcmM28qQOrxHcV6uH7g=";
  };
  mermaid-js = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";
    hash = "sha256-dNfEbavKMowilHM5EKiqHtDDdFF3bo1Sldo4ordY+5s=";
  };
  katex = fetchurl {
    url = "https://registry.npmjs.org/katex/-/katex-0.16.22.tgz";
    hash = "sha256-6eDRZ9sxdUgcutr/OOjZCxMPaj3bRRpH5DxXf9UR82U=";
  };
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
    npmFlags = [ "--ignore-scripts" ];
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      npm run typecheck
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

  nativeBuildInputs = [
    swift
    swiftPackages.swiftpm
  ];

  buildPhase = ''
    runHook preBuild

    mkdir -p Deps
    cp -R ${swift-markdown} Deps/swift-markdown
    cp -R ${swift-cmark} Deps/cmark
    chmod -R u+w Deps

    export NOSTR_CHAT_BAR_SWIFT_MARKDOWN_PATH=Deps/swift-markdown
    export SWIFTCI_USE_LOCAL_DEPS=1
    swift build -c release --disable-sandbox
    cp .build/release/nostr-chat-bar nostr-chat-bar

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/nostr-chat-bar
    install -m 755 nostr-chat-bar $out/bin/nostr-chat-bar
    install -m 644 NostrChatBar.icns $out/share/nostr-chat-bar/NostrChatBar.icns
    install -m 644 NoaMenuBarTemplate.png $out/share/nostr-chat-bar/NoaMenuBarTemplate.png
    install -m 644 ${mermaid-js} $out/share/nostr-chat-bar/mermaid.min.js
    tar -xzf ${katex}
    install -m 644 package/dist/katex.min.js $out/share/nostr-chat-bar/katex.min.js
    install -m 644 package/dist/katex.min.css $out/share/nostr-chat-bar/katex.min.css
    cp -R package/dist/fonts $out/share/nostr-chat-bar/fonts
    mkdir -p $out/share/nostr-chat-bar/web
    cp -R ${webAssets}/dist/. $out/share/nostr-chat-bar/web/
    runHook postInstall
  '';

  meta = {
    description = "macOS menubar chat panel for nostr-chatd";
    license = with lib.licenses; [
      mit
      asl20
      bsd2
    ];
    platforms = lib.platforms.darwin;
    mainProgram = "nostr-chat-bar";
  };
}
