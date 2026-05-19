{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "meetily";
  version = "0.3.0";

  src = fetchurl {
    url = "https://github.com/Zackriya-Solutions/meeting-minutes/releases/download/v${version}/meetily_${version}_aarch64.dmg";
    hash = "sha256-hPF1FkGHRZlxJeFOhFWi/cTYe63VGAayTzNwWZMjxS8=";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r meetily.app $out/Applications/
    runHook postInstall
  '';

  meta = with lib; {
    description = "AI-powered meeting minutes application";
    homepage = "https://github.com/Zackriya-Solutions/meeting-minutes";
    license = licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
