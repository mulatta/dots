{
  lib,
  python3,
  python3Packages,
  makeWrapper,
  nix-update,
  nix-prefetch-git,
  prefetch-npm-deps,
  nix,
  git,
  gh,
}:

python3Packages.buildPythonApplication {
  pname = "updater";
  version = "0.1.0";
  pyproject = false;

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/updater $out/bin
    cp -r *.py $out/lib/updater/

    makeWrapper ${python3}/bin/python3 $out/bin/updater \
      --add-flags "-m updater" \
      --prefix PATH : ${
        lib.makeBinPath [
          nix-update
          nix-prefetch-git
          prefetch-npm-deps
          nix
          git
          gh
        ]
      } \
      --set PYTHONPATH $out/lib

    runHook postInstall
  '';

  meta = {
    description = "Package updater for dotfiles";
    mainProgram = "updater";
  };
}
