{
  lib,
  python3Packages,
}:

let
  py = python3Packages;
in
py.buildPythonApplication {
  pname = "n8n-hooks";
  version = "0.1.0";

  src = ./.;

  pyproject = true;

  build-system = [ py.hatchling ];

  dependencies = [ py.pyyaml ];

  nativeCheckInputs = [
    py.mypy
    py.pytest
    py.ruff
    py.types-pyyaml
  ];

  checkPhase = ''
    runHook preCheck

    ruff format --check .
    ruff check .
    mypy n8n_hooks tests
    pytest tests/

    runHook postCheck
  '';

  meta = {
    description = "CLI to invoke n8n webhooks for email drafts, read-only context, Vikunja tasks, and Linkwarden links";
    mainProgram = "n8n-hooks";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
