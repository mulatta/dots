{
  lib,
  buildNpmPackage,
  rhwp-wasm,
  rhwpSrc,
  version,
}:
buildNpmPackage {
  pname = "rhwp-studio";
  inherit version;
  src = rhwpSrc;
  sourceRoot = "source/rhwp-studio";

  npmDepsHash = "sha256-y9Tw9S+oh6DQVy5wjNoKtudhuVU9omLDrjHyS6DRiT8=";

  # Vite expects wasm bundle next to rhwp-studio.
  preBuild = ''
    chmod -R u+w ..
    mkdir -p ../pkg
    cp -r ${rhwp-wasm}/* ../pkg/
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r dist/* $out/
    runHook postInstall
  '';

  meta = {
    description = "rhwp-studio static bundle (Vite build)";
    license = lib.licenses.mit;
  };
}
