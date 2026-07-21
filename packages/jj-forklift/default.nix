{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  gitMinimal,
  gh,
  jujutsu,
  jjui,
}:

rustPlatform.buildRustPackage rec {
  pname = "jj-forklift";
  version = "0.1.0-unstable-2026-07-10";

  src = fetchFromGitHub {
    owner = "rivet-dev";
    repo = "jj-forklift";
    rev = "f1d50a5c8af22c42ae17c5a0d10b7db8ee6b2758";
    hash = "sha256-UPkdgU8l23LS12nVCFGX2b7DUJY95UYFv9xMLnOK1CM=";
  };

  cargoHash = "sha256-YptPd3AzONuSEECdPg40QY++7U0tNVTROekKQgsJqbI=";

  VERGEN_GIT_BRANCH = "main";
  VERGEN_GIT_COMMIT_COUNT = "0";
  VERGEN_GIT_COMMIT_DATE = "2026-07-10";
  VERGEN_GIT_COMMIT_TIMESTAMP = "2026-07-10T21:53:10Z";
  VERGEN_GIT_DESCRIBE = "f1d50a5c8af22c42ae17c5a0d10b7db8ee6b2758";
  VERGEN_GIT_DIRTY = "false";
  VERGEN_GIT_SHA = "f1d50a5c8af22c42ae17c5a0d10b7db8ee6b2758";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  nativeCheckInputs = [
    gitMinimal
    gh
    jujutsu
  ];

  postInstall = ''
    wrapProgram $out/bin/forklift \
      --prefix PATH : ${
        lib.makeBinPath [
          gitMinimal
          gh
          jujutsu
          jjui
        ]
      }
  '';

  # Integration tests shell out to GitHub CLI and local Git remotes; keep the
  # Nix package build focused on reproducible compilation.
  doCheck = false;

  meta = {
    description = "Jujutsu-native stacked PR workflow for GitHub";
    homepage = "https://github.com/rivet-dev/jj-forklift";
    license = lib.licenses.asl20;
    mainProgram = "forklift";
    platforms = lib.platforms.unix;
  };
}
