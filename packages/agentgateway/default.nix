{
  lib,
  rustPlatform,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs_24,
  pnpm_11,
  pnpmConfigHook,
  cmake,
  perl,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agentgateway";
  version = "1.7.0";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "agentgateway";
    repo = "agentgateway";
    tag = "v${finalAttrs.version}";
    hash = "sha256-otrX0zLcDb/QPrErHmvW4eihsV1WEcnsE1jFlnp1pwI=";
  };

  cargoHash = "sha256-tcF+rj+WPUwil+kQA1dbkLK/ybLt0CJTGi7qmeMyo94=";

  frontend = stdenvNoCC.mkDerivation (uiAttrs: {
    pname = "${finalAttrs.pname}-ui";
    inherit (finalAttrs) version src;

    # Schema generation reads ../schema from the full source archive.
    sourceRoot = "${uiAttrs.src.name}/ui";

    pnpmDeps = fetchPnpmDeps {
      inherit (uiAttrs)
        pname
        version
        src
        sourceRoot
        ;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-dvs1zkJarSRGIP8KuKgB8EuRVN05J79EURFTE9MJ5lQ=";
    };

    nativeBuildInputs = [
      nodejs_24
      pnpm_11
      pnpmConfigHook
    ];

    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/agentgateway/ui"
      cp -r dist/. "$out/share/agentgateway/ui/"
      runHook postInstall
    '';
  });

  cargoBuildFlags = [
    "--package"
    "agentgateway-app"
  ];
  cargoTestFlags = [
    "--package"
    "agentgateway"
    "--lib"
  ];
  buildFeatures = [ "agentgateway-app/ui" ];
  checkFeatures = [ "ui" ];

  # Other library suites start external services or fetch remote resources.
  checkFlags = [
    "config::tests::"
    "http::route::tests::"
  ];
  dontUseCargoParallelTests = true;

  nativeBuildInputs = [
    cmake
    perl
  ];
  dontUseCmakeConfigure = true;

  env = {
    VERSION = finalAttrs.version;
    GIT_REVISION = finalAttrs.src.tag;
  };

  postPatch = ''
    patchShebangs tools/report_build_info.sh
  '';

  preBuild = ''
    mkdir -p ui/dist
    cp -r ${finalAttrs.frontend}/share/agentgateway/ui/. ui/dist/
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = [ "-V" ];
  postInstallCheck = ''
    "$out/bin/agentgateway" --validate-only --config \
      '{"binds":[{"port":18080,"listeners":[{"routes":[{"policies":{"directResponse":{"status":200,"body":"ok"}}}]}]}]}'
  '';

  meta = {
    description = "Gateway for LLM, MCP, and A2A traffic";
    homepage = "https://agentgateway.dev";
    changelog = "https://github.com/agentgateway/agentgateway/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "agentgateway";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
