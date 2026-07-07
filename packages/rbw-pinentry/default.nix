{
  python3Packages,
  lib,
  makeWrapper,
  zenity,
}:

let
  py = python3Packages;
in
py.buildPythonApplication {
  pname = "rbw-pinentry";
  version = "0.1.0";
  format = "pyproject";

  src = ./.;

  meta.mainProgram = "rbw-pinentry";

  nativeBuildInputs = [
    py.hatchling
    makeWrapper
  ];

  propagatedBuildInputs = [
    py.keyring
  ];

  pythonImportsCheck = [ "rbw_pinentry" ];

  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests
    runHook postCheck
  '';

  postInstall = ''
    wrapProgram $out/bin/rbw-pinentry \
      --prefix PATH : ${lib.makeBinPath [ zenity ]}
  '';
}
