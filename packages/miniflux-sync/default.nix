{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "miniflux-sync";
  version = "0.1.0";

  src = ./.;

  pyproject = true;

  build-system = [ python3Packages.hatchling ];

  dependencies = [
    python3Packages.miniflux
    python3Packages.psycopg
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages.ruff
  ];

  checkPhase = ''
    runHook preCheck
    ruff format --check .
    ruff check .
    pytest
    runHook postCheck
  '';

  meta = {
    description = "Idempotent sync of Miniflux assets and feeds from a JSON manifest";
    mainProgram = "miniflux-sync";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
