{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  makeWrapper,
}:

buildNpmPackage (finalAttrs: {
  pname = "instagram-cli";
  version = "1.4.3";

  src = fetchFromGitHub {
    owner = "supreme-gg-gg";
    repo = "instagram-cli";
    tag = "ts-v${finalAttrs.version}";
    hash = "sha256-EJxTPCiEOJG1AwWnsOrCIW/TQsrB1Kl678uocaWYC10=";
  };

  npmDepsHash = "sha256-hUX+xZD3CDgPFwZtr91bJTC6JTXzIzgjn90QME+iMwE=";

  nodejs = nodejs_22;

  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  # Skip lifecycle scripts during npm install to avoid:
  # - sharp trying to download/build native bindings (prebuilt @img/sharp-* suffices)
  # - esbuild install.js version check (binary comes from @esbuild/*)
  npmInstallFlags = [ "--ignore-scripts" ];

  # Keep dontNpmPrune so buildNpmPackage doesn't prune before build
  # (devDeps like esbuild/typescript are needed). Manual prune after build.
  dontNpmPrune = true;

  buildPhase = ''
    runHook preBuild

    # patch-package postinstall was skipped, run manually
    node node_modules/.bin/patch-package

    # tsc --noEmit && node esbuild.config.mjs --production
    npm run build

    # Remove devDependencies to shrink closure
    npm prune --omit=dev --ignore-scripts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/instagram-cli}
    cp -r dist $out/lib/instagram-cli/
    cp -r node_modules $out/lib/instagram-cli/

    makeWrapper ${lib.getExe nodejs_22} $out/bin/instagram-cli \
      --add-flags "$out/lib/instagram-cli/dist/cli.js"

    runHook postInstall
  '';

  meta = with lib; {
    description = "The unofficial CLI and terminal client for Instagram";
    homepage = "https://github.com/supreme-gg-gg/instagram-cli";
    license = licenses.mit;
    maintainers = [ maintainers.mulatta ];
    mainProgram = "instagram-cli";
  };
})
