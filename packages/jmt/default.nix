{
  python3,
  lib,
  makeWrapper,
  nix,
  jujutsu,
  uutils-coreutils-noprefix,
}:
python3.pkgs.buildPythonApplication {
  pname = "jmt";
  version = "0.1.0";
  pyproject = false;

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = with python3.pkgs; [
    tomli # For Python < 3.11 compatibility
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 jmt.py $out/bin/jmt
    wrapProgram $out/bin/jmt \
      --prefix PATH : ${
        lib.makeBinPath [
          nix
          jujutsu
        ]
      } \
      --set JMT_MKTEMP "${uutils-coreutils-noprefix}/bin/mktemp"
    runHook postInstall
  '';

  meta = {
    description = "Format commits with jj fix using flake's treefmt config";
    mainProgram = "jmt";
  };
}
