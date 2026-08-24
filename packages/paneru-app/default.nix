{
  lib,
  stdenvNoCC,
  rcodesign,
  paneru,
}:
let
  daemon = paneru;
  appName = "Paneru.app";
  bundleVersion = builtins.head (lib.splitString "+" daemon.version);
  executable = "${appName}/Contents/MacOS/paneru";
in
stdenvNoCC.mkDerivation {
  pname = "paneru-app";
  inherit (daemon) version;

  dontUnpack = true;
  dontFixup = true;
  nativeBuildInputs = [ rcodesign ];

  installPhase = ''
    runHook preInstall

    app="$out/Applications/${appName}"
    install -Dm755 ${lib.getExe daemon} "$app/Contents/MacOS/paneru"
    install -Dm644 ${./Info.plist} "$app/Contents/Info.plist"
    substituteInPlace "$app/Contents/Info.plist" \
      --replace-fail '@VERSION@' "${bundleVersion}"

    mkdir -p "$out/bin"
    ln -s "../Applications/${executable}" "$out/bin/paneru"

    rcodesign sign --timestamp-url none "$app"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ rcodesign ];
  installCheckPhase = ''
    test -x "$out/Applications/${executable}"
    test ! -L "$out/Applications/${executable}"
    test "$(readlink "$out/bin/paneru")" = "../Applications/${executable}"
    /usr/bin/codesign --verify --deep --strict "$out/Applications/${appName}"
    "$out/bin/paneru" --version | grep -F "paneru "
  '';

  passthru = daemon.passthru // {
    inherit daemon;
  };

  meta = daemon.meta // {
    description = "Signed macOS app bundle for the Paneru window manager";
    mainProgram = "paneru";
  };
}
