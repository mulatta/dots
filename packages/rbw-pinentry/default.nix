{
  python3Packages,
  lib,
  stdenv,
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

  pythonImportsCheck = [ "rbw_pinentry.cli" ];

  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests
    runHook postCheck
  '';

  # macOS uses the system osascript dialog.
  postInstall = lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
    wrapProgram $out/bin/rbw-pinentry \
      --prefix PATH : ${lib.makeBinPath [ zenity ]}
  '';
}
