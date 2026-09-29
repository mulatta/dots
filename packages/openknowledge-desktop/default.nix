{
  fetchurl,
  lib,
  stdenvNoCC,
  undmg,
}:

let
  srcs = lib.importJSON ./srcs.json;
in
stdenvNoCC.mkDerivation {
  pname = "openknowledge-desktop";
  inherit (srcs) version;

  src = fetchurl {
    inherit (srcs) url hash;
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R OpenKnowledge.app "$out/Applications/"
    runHook postInstall
  '';

  # Fixups mutate signed Mach-O files and invalidate upstream's app signature.
  dontFixup = true;

  meta = {
    description = "Local-first Markdown knowledge base desktop application";
    homepage = "https://openknowledge.ai";
    license = lib.licenses.gpl3Plus;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
