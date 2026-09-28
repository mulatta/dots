{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "termaid";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "fasouto";
    repo = "termaid";
    tag = "v${finalAttrs.version}";
    hash = "sha256-PIpciXaiduwBOvDcbEglywfFFZZ7bdEAMuT8vac8oRQ=";
  };

  pyproject = true;

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    rich
    textual
  ];

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-snapshot
  ];

  pythonImportsCheck = [ "termaid" ];

  meta = {
    description = "Render Mermaid diagrams in terminal or Python apps";
    homepage = "https://github.com/fasouto/termaid";
    license = lib.licenses.mit;
    mainProgram = "termaid";
    platforms = lib.platforms.all;
  };
})
