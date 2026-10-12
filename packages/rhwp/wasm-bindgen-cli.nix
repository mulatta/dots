{
  buildWasmBindgenCli,
  fetchCrate,
  rustPlatform,
  wasmBindgenVersion,
}:
let
  # Must match rhwp's wasm-bindgen crate version.
  version = wasmBindgenVersion;

  src = fetchCrate {
    pname = "wasm-bindgen-cli";
    inherit version;
    hash = "sha256-di+qBAdd7pENLiIB9CoZoab+W5xeDoByMREcCGTSzWo=";
  };
in
buildWasmBindgenCli {
  inherit src;
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    inherit (src) pname version;
    hash = "sha256-FTv2GZIAQs0ePdIZXIXil7JbZ6kIT05VG6vqC1qNFxQ=";
  };
}
