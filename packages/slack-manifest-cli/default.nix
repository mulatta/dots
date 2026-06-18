{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "slack-manifest-cli";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.pyyaml ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages.ruff
    python3Packages.types-pyyaml
    python3Packages.mypy
  ];

  pythonImportsCheck = [ "slack_manifest_cli" ];

  preCheck = ''
    ruff check .
    ruff format --check .
    mypy slack_manifest_cli tests
  '';

  meta = {
    description = "CLI to manage Slack app manifests from raw YAML or JSON files";
    mainProgram = "slack-manifest";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
