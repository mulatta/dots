{
  lib,
  cargoHash,
  rhwpSrc,
  rustPlatform,
  version,
}:
rustPlatform.buildRustPackage {
  pname = "rhwp-cli";
  inherit version;
  src = rhwpSrc;

  inherit cargoHash;

  # Build only consumer-facing CLI.
  cargoBuildFlags = [
    "--locked"
    "--bin"
    "rhwp"
  ];

  doCheck = false;

  meta = {
    description = "rhwp native CLI: HWP/HWPX → SVG/PDF";
    license = lib.licenses.mit;
    mainProgram = "rhwp";
  };
}
