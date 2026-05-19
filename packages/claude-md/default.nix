{
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "claude-md";
  version = "0.1.0";
  src = ./.;
  pyproject = true;
  build-system = [ python3Packages.hatchling ];
  meta = {
    description = "CLI tool to manage CLAUDE.local.md files across repositories";
    mainProgram = "claude-md";
  };
}
