{
  lib,
  python3,
  python3Packages,
  makeWrapper,
  nix-update,
  nix-prefetch-docker,
  nix-prefetch-git,
  prefetch-npm-deps,
  nix,
  nodejs,
  git,
  gh,
}:

python3Packages.buildPythonApplication {
  pname = "updater";
  version = "0.1.0";
  pyproject = false;

  # Regression tests exercise sibling update scripts using their real layout.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./.
      ../radicle-desktop/update.py
      ../neko-image/update.py
      ../neko-image/default.nix
    ];
  };
  sourceRoot = "source/updater";

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  doCheck = true;
  preCheck = ''
    export PYTHONPATH="$PWD/..''${PYTHONPATH:+:$PYTHONPATH}"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/updater $out/bin
    cp -r *.py $out/lib/updater/

    makeWrapper ${python3}/bin/python3 $out/bin/updater \
      --add-flags "-m updater" \
      --prefix PATH : ${
        lib.makeBinPath [
          nix-update
          nix-prefetch-docker
          nix-prefetch-git
          prefetch-npm-deps
          nix
          nodejs
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
