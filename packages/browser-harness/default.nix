{
  lib,
  python3,
  callPackage,
  fetchFromGitHub,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
  writableTmpDirAsHomeHook,
  ps,
}:

let
  # Shared with browser-use, which imports browser_harness.
  pythonOverrides = lib.composeExtensions (callPackage ./python-mcp2.nix { }) (
    pyFinal: _pyPrev: {
      cdp-use = pyFinal.buildPythonPackage (finalAttrs: {
        pname = "cdp-use";
        version = "1.4.5";
        pyproject = true;

        src = fetchPypi {
          pname = "cdp_use";
          inherit (finalAttrs) version;
          hash = "sha256-DaOjLfRjNqA/9aIrxrxELNfS8tUKEY/UhW8p039tJqA=";
        };

        build-system = [ pyFinal.hatchling ];

        dependencies = with pyFinal; [
          httpx
          typing-extensions
          websockets
        ];

        pythonImportsCheck = [ "cdp_use" ];

        meta = {
          description = "Type-safe client library for the Chrome DevTools Protocol";
          homepage = "https://github.com/browser-use/cdp-use";
          license = lib.licenses.mit;
        };
      });

      fetch-use = pyFinal.buildPythonPackage (finalAttrs: {
        pname = "fetch-use";
        version = "0.4.0";
        pyproject = true;

        src = fetchPypi {
          pname = "fetch_use";
          inherit (finalAttrs) version;
          hash = "sha256-lRGYfUkH7G2sUB4h1mlG0QCY9mtdIbwqukGJzYG6GJo=";
        };

        build-system = [ pyFinal.hatchling ];

        pythonImportsCheck = [ "fetch_use" ];

        meta = {
          description = "Python client for the Browser-Use Fetch HTTP service";
          homepage = "https://github.com/browser-use/fetch-use";
          license = lib.licenses.mit;
        };
      });

      browser-harness = pyFinal.buildPythonPackage (finalAttrs: {
        pname = "browser-harness";
        version = "0.1.13";
        pyproject = true;

        src = fetchFromGitHub {
          owner = "browser-use";
          repo = "browser-harness";
          tag = "v${finalAttrs.version}";
          hash = "sha256-sFg3eQnM5gOnESHsQGHi3hoeN5pjnmFAETgY61qBjI4=";
        };

        # Upstream pins its build backend exactly.
        pypaBuildFlags = [ "--skip-dependency-check" ];

        build-system = [ pyFinal.setuptools ];

        pythonRelaxDeps = true;

        dependencies = with pyFinal; [
          cdp-use
          fetch-use
          mcp
          pillow
          websockets
        ];

        makeWrapperArgs = [
          # The daemon runs as a bare `python -m browser_harness.daemon`.
          "--prefix"
          "PYTHONPATH"
          ":"
          "${placeholder "out"}/${pyFinal.python.sitePackages}:${pyFinal.makePythonPath finalAttrs.passthru.dependencies}"
          # Nix handles updates.
          "--set-default"
          "BH_UPDATE_CHECK"
          "0"
        ];

        nativeCheckInputs = [
          pyFinal.pytestCheckHook
          writableTmpDirAsHomeHook
          # Needed on darwin by _process_start_time.
          ps
        ];

        enabledTestPaths = [ "tests/unit" ];

        pythonImportsCheck = [
          "browser_harness"
          "browser_harness.daemon"
          "browser_harness.helpers"
          "mcp_server"
        ];

        doInstallCheck = true;
        nativeInstallCheckInputs = [
          versionCheckHook
          versionCheckHomeHook
        ];
        versionCheckProgramArg = "--version";

        passthru = { inherit pythonOverrides; };

        meta = {
          description = "Thin harness that lets AI agents control a real Chrome browser over CDP";
          homepage = "https://github.com/browser-use/browser-harness";
          changelog = "https://github.com/browser-use/browser-harness/releases/tag/v${finalAttrs.version}";
          license = lib.licenses.mit;
          sourceProvenance = with lib.sourceTypes; [ fromSource ];
          mainProgram = "browser-harness";
          platforms = lib.platforms.all;
        };
      });
    }
  );

  python = python3.override {
    self = python;
    packageOverrides = pythonOverrides;
  };
in
python.pkgs.toPythonApplication python.pkgs.browser-harness
