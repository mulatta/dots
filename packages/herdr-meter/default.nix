{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "hmeter";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Agent prompt cache and account usage snapshots for herdr";
    mainProgram = "hmeter";
  };
}
