{
  python3,
  openssh,
  gitMinimal,
  jujutsu,
  jmt,
  gh,
  tea,
  coreutils,
  lib,
  makeWrapper,
}:
let
  runtimeDeps = [
    jujutsu
    jmt
    gitMinimal # for read-only git commands (remote, symbolic-ref)
    coreutils
    gh
    tea
  ];
in
python3.pkgs.buildPythonApplication {
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
    description = "Merge a PR when CI is green - jujutsu version (supports GitHub and Gitea)";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "merge-when-green";
  };
}
