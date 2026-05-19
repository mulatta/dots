{
  python3Packages,
  openssh,
  gitMinimal,
  flake-fmt,
  gh,
  coreutils,
  lib,
  makeWrapper,
}:
let
  runtimeDeps = [
    flake-fmt
    gitMinimal
    coreutils
    gh
  ];
in
python3Packages.buildPythonApplication {
  pname = "merge-when-green";
  version = "0.4.0";
  src = ./.;
  format = "other";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -D -m 0755 merge-when-green.py $out/bin/merge-when-green

    wrapProgram $out/bin/merge-when-green \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --suffix PATH : ${lib.makeBinPath [ openssh ]}
  '';

  meta = with lib; {
    description = "Merge a GitHub PR when CI is green";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "merge-when-green";
  };
}
