{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
  node-gyp,
  python3,
  kdePackages,
  # TREK anchors data/ and uploads/ on its install tree (server/src/app-config/data-paths.ts).
  stateDir ? "/var/lib/trek",
}:

buildNpmPackage (finalAttrs: {
  pname = "trek";
  version = "5.2.2";

  src = fetchFromGitHub {
    owner = "liketrek";
    repo = "TREK";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/ysj/fNyZHtNaw7usBgu6xGNmWKb+/bqbnAE1fvzqkA=";
  };

  npmDepsHash = "sha256-kfnnB1o3miI4VFaQXJA4if18cH56wIA62m7et+A9FyM=";

  inherit nodejs;

  nativeBuildInputs = [
    makeWrapper
    node-gyp
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # @napi-rs/canvas ships a prebuilt Skia addon linked against libstdc++.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  env.SCARF_ANALYTICS = "false";

  # plyr's preinstall runs `npx only-allow pnpm`, which needs the network.
  npmRebuildFlags = [ "--ignore-scripts" ];

  # npmConfigHook patches shebangs only in the root node_modules.
  postConfigure = ''
    patchShebangs {client,server,shared}/node_modules
  '';

  installPhase = ''
    runHook preInstall

    rm -rf node_modules server/node_modules shared/node_modules
    npm ci --workspace=server --omit=dev --ignore-scripts

    # better-sqlite3's binding.gyp skips compiling when a bundled prebuild matches the host.
    pushd node_modules/better-sqlite3
    rm -r prebuilds
    node-gyp rebuild --release
    find build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -r {} +
    find build/Release -mindepth 1 -maxdepth 1 ! -name better_sqlite3.node -exec rm -r {} +
    rm -r deps src binding.gyp
    popd

    # bare-fs and others ship prebuilds for every platform, which trip autoPatchelf.
    find node_modules -type d -name prebuilds -prune | while read -r dir; do
      find "$dir" -mindepth 1 -maxdepth 1 \
        ! -name '${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}' -exec rm -r {} +
    done
    rm -rf node_modules/@napi-rs/canvas-*-musl

    app=$out/lib/trek
    mkdir -p $app/shared $app/server/scripts

    cp -r node_modules $app/node_modules
    cp -r server/node_modules $app/server/node_modules

    cp shared/package.json $app/shared/
    cp -r shared/dist $app/shared/dist

    cp server/package.json server/tsconfig.json server/reset-admin.js $app/server/
    cp server/scripts/migrate-encryption.ts server/scripts/migrate-encryption-stores.ts $app/server/scripts/
    cp -r server/dist server/assets $app/server/
    cp -r client/dist $app/server/public
    cp -r client/public/fonts $app/server/public/fonts
    cp -r wiki $app/wiki

    ln -s ${stateDir}/data $app/server/data
    ln -s ${stateDir}/uploads $app/server/uploads

    # tsconfig-paths/register resolves tsconfig.json from the working directory.
    makeWrapper ${lib.getExe nodejs} $out/bin/trek \
      --chdir $app/server \
      --set-default NODE_ENV production \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        --set-default KITINERARY_EXTRACTOR_PATH ${kdePackages.kitinerary}/libexec/kf6/kitinerary-extractor \
        --set-default QT_QPA_PLATFORM offscreen \
      ''} \
      --add-flags "--require tsconfig-paths/register dist/index.js"

    runHook postInstall
  '';

  dontCheckForBrokenSymlinks = true;

  meta = {
    description = "Self-hosted collaborative travel and trip planner";
    homepage = "https://github.com/liketrek/TREK";
    changelog = "https://github.com/liketrek/TREK/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "trek";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
