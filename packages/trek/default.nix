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
  # The server resolves its SQLite database and uploads relative to its own
  # install tree (server/data, server/uploads), so mutable state has to be
  # reached through symlinks baked into the read-only store path.
  stateDir ? "/var/lib/trek",
}:

buildNpmPackage (finalAttrs: {
  pname = "trek";
  version = "4.3.3";

  src = fetchFromGitHub {
    owner = "liketrek";
    repo = "TREK";
    tag = "v${finalAttrs.version}";
    hash = "sha256-6bZN38p15ailK5tjOGj+3vePSv8iik+ABfCu0qyakKE=";
  };

  npmDepsHash = "sha256-oKXzj8Uf/dtQ/Prd4lrnabQBDC7sRth3NuIwowV2ROY=";

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

  installPhase = ''
    runHook preInstall

    # Pruning from the root keeps the client workspace's runtime deps (map
    # libraries, icon sets), which only matter for the already built bundle.
    # Reinstall the server workspace alone, as the upstream image does.
    rm -rf node_modules server/node_modules shared/node_modules
    npm ci --workspace=server --omit=dev --ignore-scripts

    # better-sqlite3 carries prebuilt addons in its tarball and its binding.gyp
    # skips compilation whenever one matches the host. Removing them forces
    # node-gyp to compile the bundled SQLite amalgamation against this nodejs.
    pushd server/node_modules/better-sqlite3
    rm -r prebuilds
    node-gyp rebuild --release
    find build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -r {} +
    find build/Release -mindepth 1 -maxdepth 1 ! -name better_sqlite3.node -exec rm -r {} +
    rm -r deps src binding.gyp
    popd

    # Packages like bare-fs ship addons for every platform; foreign ones
    # would only trip autoPatchelf.
    find node_modules -type d -name prebuilds -prune | while read -r dir; do
      find "$dir" -mindepth 1 -maxdepth 1 \
        ! -name '${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}' -exec rm -r {} +
    done
    rm -rf node_modules/@napi-rs/canvas-*-musl

    app=$out/lib/trek
    mkdir -p $app/shared $app/server/scripts

    cp -r node_modules $app/node_modules
    # better-sqlite3 is not hoisted, so server keeps its own node_modules.
    cp -r server/node_modules $app/server/node_modules

    cp shared/package.json $app/shared/
    cp -r shared/dist $app/shared/dist

    cp server/package.json server/tsconfig.json server/reset-admin.js $app/server/
    cp server/scripts/migrate-encryption.ts $app/server/scripts/
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

  # The state symlinks point outside the store until the service creates them.
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
