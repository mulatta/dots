{
  lib,
  stdenv,
  python3,
  fetchFromGitHub,
  fetchPypi,
  browser-harness,
  writableTmpDirAsHomeHook,
}:

let
  python = python3.override {
    self = python;
    packageOverrides = lib.composeExtensions browser-harness.pythonOverrides (
      pyFinal: _pyPrev: {
        uuid7 = pyFinal.buildPythonPackage (finalAttrs: {
          pname = "uuid7";
          version = "0.1.0";
          pyproject = true;

          src = fetchPypi {
            inherit (finalAttrs) pname version;
            hash = "sha256-jFeqMu50VtPMaMlcRTC8VxZG3vrAGJXPxzVFRJiUpjw=";
          };

          build-system = [ pyFinal.setuptools ];

          pythonImportsCheck = [ "uuid_extensions" ];

          meta = {
            description = "UUID version 7, generating time-sorted UUIDs";
            homepage = "https://github.com/stevesimmons/uuid7";
            license = lib.licenses.mit;
          };
        });

        bubus = pyFinal.buildPythonPackage (finalAttrs: {
          pname = "bubus";
          version = "1.5.6";
          pyproject = true;

          src = fetchPypi {
            inherit (finalAttrs) pname version;
            hash = "sha256-GlRW8KV26GYTp71m6BmJG2d3eDILbikQlOM5sNnfLg0=";
          };

          build-system = [ pyFinal.hatchling ];

          dependencies = with pyFinal; [
            aiofiles
            anyio
            portalocker
            pydantic
            typing-extensions
            uuid7
          ];

          pythonImportsCheck = [ "bubus" ];

          meta = {
            description = "Pydantic-based event bus for async Python";
            homepage = "https://github.com/browser-use/bubus";
            license = lib.licenses.mit;
          };
        });

        browser-use-sdk = pyFinal.buildPythonPackage (finalAttrs: {
          pname = "browser-use-sdk";
          version = "3.4.2";
          pyproject = true;

          src = fetchPypi {
            pname = "browser_use_sdk";
            inherit (finalAttrs) version;
            hash = "sha256-vgULyAOzHsTp8j39cdncXxFg197AuWIyeRXK90OhAgg=";
          };

          build-system = [ pyFinal.hatchling ];

          dependencies = with pyFinal; [
            httpx
            pydantic
          ];

          pythonImportsCheck = [ "browser_use_sdk" ];

          meta = {
            description = "Python SDK for the Browser Use cloud API";
            homepage = "https://github.com/browser-use/browser-use";
            license = lib.licenses.mit;
          };
        });
      }
    );
  };
in
python.pkgs.buildPythonApplication (finalAttrs: {
  pname = "browser-use";
  version = "0.13.11";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "browser-use";
    repo = "browser-use";
    tag = finalAttrs.version;
    hash = "sha256-Pic/5ZYFIdOfiCkXt6VPkLhQRzjByu6k/e5uFCoD010=";
  };

  patches = [
    # Upstream only probes fixed Chrome paths, then tries uvx playwright.
    ./find-browser-on-path.patch
  ];

  # Upstream pins its build backend exactly.
  pypaBuildFlags = [ "--skip-dependency-check" ];

  build-system = [ python.pkgs.hatchling ];

  # Relax upstream's exact pins.
  pythonRelaxDeps = true;
  # Optional screen-size probe; upstream's darwin marker never matches.
  pythonRemoveDeps = lib.optionals stdenv.hostPlatform.isDarwin [ "screeninfo" ];

  dependencies =
    with python.pkgs;
    [
      aiohttp
      anthropic
      anyio
      # The argument of the same name is the application.
      python.pkgs.browser-harness
      browser-use-sdk
      bubus
      cdp-use
      click
      cloudpickle
      google-api-core
      google-api-python-client
      google-auth
      google-auth-oauthlib
      google-genai
      groq
      httpx
      inquirerpy
      markdownify
      mcp
      ollama
      openai
      pillow
      posthog
      psutil
      pydantic
      pydantic-settings
      pyotp
      pypdf
      python-docx
      python-dotenv
      reportlab
      requests
      rich
      typing-extensions
      uuid7
    ]
    ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [ screeninfo ];

  makeWrapperArgs = [
    # The harness daemon runs as a bare `python -m browser_harness.daemon`.
    "--prefix"
    "PYTHONPATH"
    ":"
    "${placeholder "out"}/${python.sitePackages}:${python.pkgs.makePythonPath finalAttrs.passthru.dependencies}"
    "--set-default"
    "BH_UPDATE_CHECK"
    "0"
  ];

  pythonImportsCheck = [
    "browser_use"
    "browser_use.cli"
  ];

  # --version reports browser-harness's version.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/browser-use --help | grep -q 'browser-use doctor'
    runHook postInstallCheck
  '';

  meta = {
    description = "Make websites accessible for AI agents";
    homepage = "https://browser-use.com";
    changelog = "https://github.com/browser-use/browser-use/releases/tag/${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "browser-use";
    platforms = lib.platforms.all;
  };
})
