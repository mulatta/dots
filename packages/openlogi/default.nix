{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

let
  srcs = lib.importJSON ./srcs.json;
in
stdenvNoCC.mkDerivation {
  pname = "openlogi";
  inherit (srcs) version;

  src = fetchurl {
    inherit (srcs) url hash;
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R OpenLogi.app "$out/Applications/"
    ln -s ../Applications/OpenLogi.app/Contents/MacOS/openlogi "$out/bin/openlogi"
    runHook postInstall
  '';

  # Fixups mutate signed Mach-O files and break the bundle identity used by TCC.
  dontFixup = true;

  meta = {
    description = "Local-first companion for Logitech HID++ peripherals";
    homepage = "https://github.com/AprilNEA/OpenLogi";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "openlogi";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
