{
  lib,
  python3Packages,
}:

let
  py = python3Packages;
in
py.buildPythonApplication {
  pname = "addgene-mcp";
  version = "0.1.0";
  src = ./.;
  pyproject = true;
  build-system = [ py.hatchling ];
  dependencies = [
    py.mcp
    py.httpx
    py.pydantic
  ];
  nativeCheckInputs = [
    py.ruff
    py.mypy
    py.pytest
  ];
  checkPhase = ''
    runHook preCheck
    ruff format --check .
    ruff check .
    mypy addgene_mcp tests
    pytest tests/
    runHook postCheck
  '';
  pythonImportsCheck = [ "addgene_mcp" ];
  meta = {
    description = "Read-only Addgene Developers API MCP server";
    mainProgram = "addgene-mcp";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
