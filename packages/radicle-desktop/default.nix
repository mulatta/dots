{
  lib,
  stdenv,
  fetchgit,
  fetchNpmDeps,
  fetchFromGitHub,
  rust-bin,
  makeRustPlatform,
  cargo-tauri,
  nodejs,
  npmHooks,
  pkg-config,
  makeBinaryWrapper,
  # Linux
  wrapGAppsHook4,
  glib,
  gtk3,
  libsoup_3,
  openssl,
  webkitgtk_4_1,
  # macOS
  libiconv,
}:
let
  srcs = lib.importJSON ./srcs.json;

  twemojiAssets = fetchFromGitHub {
    owner = "twitter";
    repo = "twemoji";
    rev = "v14.0.2";
    hash = "sha256-YoOnZ5uVukzi/6bLi22Y8U5TpplPzB7ji42l+/ys5xI=";
  };

  src = fetchgit {
    url = "https://seed.radicle.xyz/z4D5UCArafTzTQpDZNQRuqswh3ury.git";
    rev = srcs.rev;
    hash = srcs.srcHash;
  };

  rustToolchain = rust-bin.fromRustupToolchainFile (src + "/rust-toolchain");
  rustPlatform = makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "radicle-desktop";
  version = srcs.version;

  inherit src;

  cargoLock.lockFile = src + "/Cargo.lock";

  npmDeps = fetchNpmDeps {
    name = "radicle-desktop-npm-deps";
    inherit src;
    hash = srcs.npmDepsHash;
  };

  nativeBuildInputs = [
    cargo-tauri.hook
    nodejs
    npmHooks.npmConfigHook
    pkg-config
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapGAppsHook4 ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ makeBinaryWrapper ];

  buildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      glib
      gtk3
      libsoup_3
      openssl
      webkitgtk_4_1
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  env = lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    NIX_LDFLAGS = "-framework WebKit -framework AppKit -framework Security -framework SystemConfiguration";
  };

  postPatch = ''
    patchShebangs scripts/copy-katex-assets scripts/check-js scripts/check-rs
    mkdir -p public/twemoji
    cp -t public/twemoji -r -- ${twemojiAssets}/assets/svg/*
    : >scripts/install-twemoji-assets
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p $out/bin
    makeWrapper "$out/Applications/Radicle.app/Contents/MacOS/radicle-desktop" "$out/bin/radicle-desktop"
  '';

  doCheck = false;

  meta = {
    description = "Radicle desktop app";
    homepage = "https://radicle.xyz";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "radicle-desktop";
  };
}
