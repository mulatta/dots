{
  lib,
  stdenv,
  fetchzip,
  fetchNpmDeps,
  makeWrapper,
  jdk_headless,
  nodejs,
  chromium,
}:
let
  # Chrome for Testing binary for darwin (nixpkgs chromium is linux-only)
  chromeVersion = "147.0.7727.50";
  chromeDarwin = fetchzip {
    url = "https://storage.googleapis.com/chrome-for-testing-public/${chromeVersion}/${
      if stdenv.hostPlatform.isAarch64 then "mac-arm64" else "mac-x64"
    }/chrome-${if stdenv.hostPlatform.isAarch64 then "mac-arm64" else "mac-x64"}.zip";
    hash =
      if stdenv.hostPlatform.isAarch64 then
        "sha256-SiPsmuuPjnqYthOe3Dr2TNqS79VEsHfOQiBdM0qfYxw="
      else
        "sha256-b0tf2xIltFamJeGpS2h3yljDBq/su9MpeQRP8FyL5j0=";
  };

  chromiumBin =
    if stdenv.hostPlatform.isDarwin then
      "${chromeDarwin}/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    else
      "${chromium}/bin/chromium";

  puppeteerDeps = fetchNpmDeps {
    src = ./puppeteer;
    hash = "sha256-QogrUmuaYbZAmYkkQu1TPERKGD7U59ZDkxr2CXshFvU=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "quarkdown";
  version = "2.0.1";

  src = fetchzip {
    url = "https://github.com/iamgio/quarkdown/releases/download/v${finalAttrs.version}/quarkdown.zip";
    hash = "sha256-JR4faLIPSX2Nu6W1DdWhbPvrEhxTK/1qRXNaAYFFLkg=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/lib/puppeteer

    # Distribution from release ZIP (includes bin/, lib/, docs/)
    cp -r lib/* $out/lib/
    cp -r docs $out/docs 2>/dev/null || true
    install -m755 bin/quarkdown $out/bin/quarkdown

    # Install puppeteer for PDF generation
    cp ${./puppeteer/package.json} $out/lib/puppeteer/package.json
    cp ${./puppeteer/package-lock.json} $out/lib/puppeteer/package-lock.json
    cd $out/lib/puppeteer
    export HOME=$(mktemp -d)
    npm config set offline true
    npm config set cache "${puppeteerDeps}"
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true npm ci --ignore-scripts
    cd -

    wrapProgram $out/bin/quarkdown \
      --set JAVA_HOME ${jdk_headless} \
      --set PUPPETEER_EXECUTABLE_PATH "${chromiumBin}" \
      --set QD_NPM_PREFIX "$out/lib/puppeteer" \
      --set NODE_PATH "$out/lib/puppeteer/node_modules" \
      --prefix PATH : ${
        lib.makeBinPath [
          jdk_headless
          nodejs
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Markdown with superpowers — compile to HTML, PDF, slides";
    homepage = "https://github.com/iamgio/quarkdown";
    license = lib.licenses.agpl3Only;
    mainProgram = "quarkdown";
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
  };
})
