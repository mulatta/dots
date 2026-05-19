{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  libgit2,
}:
let
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "Ataraxy-Labs";
    repo = "sem";
    rev = "v${version}";
    hash = "sha256-VdG+Ae1CGFbkqaEB6CBjtlDB13h3QxTi1GUmx+rYgXk=";
  };
in
rustPlatform.buildRustPackage {
  pname = "sem-vcs";
  inherit version src;

  # workspace lives in ./crates
  sourceRoot = "${src.name}/crates";

  cargoLock.lockFile = src + "/crates/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    openssl
    libgit2
  ];

  env = {
    OPENSSL_NO_VENDOR = "1";
    LIBGIT2_NO_VENDOR = "1";
  };

  doCheck = false;

  meta = {
    description = "Semantic version control CLI - shows entity-level diffs (functions, classes, methods)";
    homepage = "https://github.com/Ataraxy-Labs/sem";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "sem";
    platforms = lib.platforms.unix;
  };
}
