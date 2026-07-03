{
  lib,
  python3Packages,
  makeWrapper,
  omp ? null,
}:

python3Packages.buildPythonApplication {
  pname = "omp-profile";
  version = "0.1.0";
  src = ./.;
  format = "other";

  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3Packages.pyyaml ];

  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s . -p 'test_*.py'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -D -m 0755 omp_profile.py $out/bin/omp-profile
    ln -s omp-profile $out/bin/omp

    wrapProgram $out/bin/omp-profile \
      ${lib.optionalString (
        omp != null
      ) "--set OMP_PROFILE_BACKEND ${lib.escapeShellArg "${omp}/bin/omp"}"}

    runHook postInstall
  '';

  meta = {
    description = "Profile-aware OMP wrapper";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "omp";
  };
}
