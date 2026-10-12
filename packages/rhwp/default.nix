{
  callPackage,
  fetchFromGitHub,
  lib,
}:

let
  pin = lib.importJSON ./pin.json;
  args = {
    inherit (pin) version cargoHash;
    rhwpSrc = fetchFromGitHub {
      owner = "edwardkim";
      repo = "rhwp";
      inherit (pin) rev hash;
    };
  };
  wasm-bindgen-cli = callPackage ./wasm-bindgen-cli.nix {
    wasmBindgenVersion = pin.wasmBindgenVersion;
  };
  wasm = callPackage ./wasm.nix (args // { inherit wasm-bindgen-cli; });
  studio = callPackage ./studio.nix {
    inherit (args) version rhwpSrc;
    rhwp-wasm = wasm;
  };
in
(callPackage ./cli.nix args).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit studio wasm wasm-bindgen-cli;
  };
})
