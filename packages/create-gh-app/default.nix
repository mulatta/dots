{
  python3,
}:

python3.pkgs.buildPythonApplication {
  pname = "create-gh-app";
  version = "0.1.0";
  pyproject = false;

  src = ./.;

  installPhase = ''
    runHook preInstall
    install -Dm755 create_gh_app.py $out/bin/create-gh-app
    runHook postInstall
  '';

  meta = {
    description = "Helper utility to create GitHub Apps with the correct permissions";
    mainProgram = "create-gh-app";
  };
}
