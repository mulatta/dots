{
  fetchurl,
  lib,
  nodejs_24,
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
    mkdir -p "$out/Applications" "$out/bin"
    cp -R OpenKnowledge.app "$out/Applications/"
    ln -s ${nodejs_24}/bin/node "$out/bin/node"
    ln -s ${nodejs_24}/bin/npm "$out/bin/npm"
    ln -s ${nodejs_24}/bin/npx "$out/bin/npx"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/node"
    test -x "$out/bin/npm"
    test -x "$out/bin/npx"
    /usr/bin/codesign --verify --deep --strict "$out/Applications/OpenKnowledge.app"
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
