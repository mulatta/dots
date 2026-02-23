{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "meetily";
  version = "0.2.1";

  src = fetchurl {
    url = "https://github.com/Zackriya-Solutions/meeting-minutes/releases/download/v${version}/meetily_${version}_aarch64.dmg";
    hash = "sha256-IIHUNOyIYPyFfeC4Q4d6yIpOK71/OY4nVTqLAuvLH/E=";
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
