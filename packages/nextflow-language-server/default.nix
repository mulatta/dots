{
  fetchurl,
  jre,
  lib,
  makeWrapper,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nextflow-language-server";
  version = "26.04.3";

  src = fetchurl {
    url = "https://github.com/nextflow-io/language-server/releases/download/v${finalAttrs.version}/language-server-all.jar";
    hash = "sha256-IM+jT24gLWuLq9jXhiAs4A4NObcMzsMpDiqz+9ArwBY=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm444 "$src" "$out/share/nextflow-language-server/language-server-all.jar"
    makeWrapper ${jre}/bin/java "$out/bin/nextflow-language-server" \
      --add-flags "-jar $out/share/nextflow-language-server/language-server-all.jar"

    runHook postInstall
  '';

  meta = {
    description = "Official language server for Nextflow";
    homepage = "https://github.com/nextflow-io/language-server";
    license = lib.licenses.asl20;
    mainProgram = "nextflow-language-server";
    platforms = lib.platforms.unix;
  };
})
