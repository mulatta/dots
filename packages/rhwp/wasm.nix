{
  lib,
  binaryen,
  cargoHash,
  lld,
  rhwpSrc,
  rustPlatform,
  version,
  wasm-bindgen-cli,
}:
rustPlatform.buildRustPackage {
  pname = "rhwp-wasm";
  inherit version;
  src = rhwpSrc;

  inherit cargoHash;

  # nixpkgs rustc ships the wasm32 standard library but links it with external lld.
  nativeBuildInputs = [
    lld
    wasm-bindgen-cli
    binaryen
  ];

  doCheck = false;

  # Avoid wasm-pack's bundled wasm-bindgen.
  buildPhase = ''
    runHook preBuild
    cargo build \
      --release \
      --lib \
      --target wasm32-unknown-unknown \
      --offline \
      --locked
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    wasm-bindgen \
      target/wasm32-unknown-unknown/release/rhwp.wasm \
      --out-dir $out \
      --target web \
      --typescript
    wasm-opt -Oz -o $out/rhwp_bg.wasm $out/rhwp_bg.wasm
    runHook postInstall
  '';

  meta = {
    description = "rhwp WASM bundle (rhwp.js + rhwp_bg.wasm)";
    license = lib.licenses.mit;
  };
}
