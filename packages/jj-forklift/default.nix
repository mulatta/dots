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
  version = "0-unstable-2026-07-21";

  src = fetchFromGitHub {
    owner = "rivet-dev";
    repo = "jj-forklift";
    rev = "8376323159c13d38dc2ddaed863a74864f5a5fa5";
    hash = "sha256-OTOCjlIw/+v/juaxfNzrTkieHVliHh5xRuKJxMzoC60=";
  };

  cargoHash = "sha256-YptPd3AzONuSEECdPg40QY++7U0tNVTROekKQgsJqbI=";

  VERGEN_GIT_BRANCH = "main";
  VERGEN_GIT_COMMIT_COUNT = "0";
  VERGEN_GIT_COMMIT_DATE = "2026-07-10";
  VERGEN_GIT_COMMIT_TIMESTAMP = "2026-07-10T21:53:10Z";
  VERGEN_GIT_DESCRIBE = "8376323159c13d38dc2ddaed863a74864f5a5fa5";
  VERGEN_GIT_DIRTY = "false";
  VERGEN_GIT_SHA = "8376323159c13d38dc2ddaed863a74864f5a5fa5";

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
