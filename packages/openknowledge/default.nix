{
  lib,
  stdenv,
  fetchPnpmDeps,
  fetchFromGitHub,
  pnpm_12,
  rustPlatform,
  cargo,
  rustc,
  pnpmConfigHook,
  pnpmBuildHook,
  nodejs_24,
  jq,
  git,
  makeBinaryWrapper,
  installAgentSkills,
  electron_44,
  makeDesktopItem,
  writeText,
  libicns,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  pname = "openknowledge";
  version = "0.83.2";
  pnpm = pnpm_12;
  electron = electron_44;
  appName = "OpenKnowledge";

  src = fetchFromGitHub {
    owner = "inkeep";
    repo = "open-knowledge";
    tag = "v${version}";
    hash = "sha256-bo+1JrXJK2bl4Q2Cp8enwB56n4RUF/CF9dwlwe0jxxk=";
  };

  # Nix supplies Node. Do not fetch upstream devEngines.runtime binaries.
  stripNodeRuntime = ''
    runtime=$(jq -r .devEngines.runtime.version package.json)
    jq 'del(.devEngines)' package.json > package.json.new
    mv package.json.new package.json
    sed -i \
      -e "/^      node:\$/{N;N;/specifier: runtime:$runtime\n/d}" \
      -e "/^  node@runtime:$runtime:/,/^\$/d" \
      pnpm-lock.yaml
    if grep -q '[@ ]runtime:' pnpm-lock.yaml; then
      echo "error: upstream pnpm-lock.yaml runtime entries changed" >&2
      exit 1
    fi
  '';

  desktopItem = makeDesktopItem {
    name = "openknowledge";
    desktopName = appName;
    exec = "openknowledge-desktop %U";
    icon = "openknowledge";
    categories = [ "Office" ];
    mimeTypes = [
      "x-scheme-handler/openknowledge"
      "text/markdown"
    ];
    startupWMClass = appName;
  };

  infoPlist = writeText "Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDevelopmentRegion = "English";
      CFBundleExecutable = appName;
      CFBundleIconFile = "openknowledge.icns";
      CFBundleIdentifier = "com.inkeep.open-knowledge";
      CFBundleInfoDictionaryVersion = "6.0";
      CFBundleName = appName;
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = version;
      CFBundleURLTypes = [
        {
          CFBundleURLName = "OpenKnowledge URL";
          CFBundleURLSchemes = [ "openknowledge" ];
          CFBundleTypeRole = "Editor";
        }
      ];
      CFBundleDocumentTypes = [
        {
          CFBundleTypeExtensions = [
            "md"
            "mdx"
          ];
          CFBundleTypeName = "Markdown Document";
          CFBundleTypeRole = "Editor";
          LSHandlerRank = "Alternate";
        }
      ];
    }
  );
in
stdenv.mkDerivation {
  inherit pname version src;

  outputs = [
    "out"
    "desktop"
  ];

  strictDeps = true;
  __structuredAttrs = true;

  pnpmDeps =
    (fetchPnpmDeps {
      inherit
        pname
        version
        src
        pnpm
        ;
      nativeBuildInputs = [ jq ];
      postPatch = stripNodeRuntime;
      fetcherVersion = 4;
      hash = "sha256-fSetGJio67EyIG2aq9OREJ3O6RE9HbiB3Tpys0Wj5Bk=";
      # Runtime download policies are irrelevant to an integrity-locked store.
      prePnpmInstall = ''
        export pnpm_config_fetch_timeout=600000
        export pnpm_config_network_concurrency=8
        export pnpm_config_trust_lockfile=true
        export pnpm_config_manage_package_manager_versions=false
        export pnpm_config_manage_runtime=false
      '';
    }).overrideAttrs
      (old: {
        # pnpm 12 leaves unpacked package copies in links/ on some platforms only.
        # Drop them so every system produces the same store hash.
        fixupPhase =
          lib.replaceStrings
            [ "rm -rf $storePath/{v3,v10,v11}/tmp" ]
            [ "rm -rf $storePath/{v3,v10,v11}/{tmp,links}" ]
            old.fixupPhase;
      });

  cargoRoot = "packages/native-config";
  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "openknowledge-native-config";
    inherit version src;
    sourceRoot = "source/packages/native-config";
    hash = "sha256-hZ/RXmDMsU3f8QpEOfw1GkKAM6qve7Ch2ckUati4Hnw=";
  };

  patches = [ ./desktop.patch ];

  postPatch = stripNodeRuntime + ''
    # Native-config uses the local Rust toolchain, not napi-cross downloads.
    substituteInPlace packages/native-config/scripts/build.mjs \
      --replace-fail "args.push('--target', target, '--use-napi-cross');" "args.push('--target', target);"
  '';

  nativeBuildInputs = [
    nodejs_24
    cargo
    rustc
    rustPlatform.cargoSetupHook
    pnpm
    pnpmConfigHook
    pnpmBuildHook
    jq
    git
    makeBinaryWrapper
    installAgentSkills
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin libicns
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;

  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  env = {
    CARGO_NET_OFFLINE = "true";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    PUPPETEER_SKIP_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    TURBO_TELEMETRY_DISABLED = "1";
    pnpm_config_manage_runtime = "false";
  };

  dontInstallAgentSkills = true;

  pnpmBuildScript = "build:desktop";
  pnpmBuildFlags = [ "--env-mode=loose" ];

  preBuild = ''
    # fetchPnpmDeps normalizes modes in the unpacked pnpm store.
    chmod +x node_modules/.pnpm/@typescript+typescript-*/node_modules/@typescript/typescript-*/lib/tsc
    chmod +x node_modules/.pnpm/@esbuild+*/node_modules/@esbuild/*/bin/esbuild
    chmod +x node_modules/.pnpm/@turbo+*/node_modules/@turbo/*/bin/turbo

    for name in cli core server app desktop; do
      jq --arg version ${version} '.version = $version' "packages/$name/package.json" > package.json.new
      mv package.json.new "packages/$name/package.json"
    done
    node scripts/create-turbo-cache-key.mjs
  '';

  installPhase = ''
    runHook preInstall

    pnpm --filter @inkeep/open-knowledge deploy --prod --offline --ignore-scripts "$out/libexec/openknowledge/cli"
    mkdir -p "$out/bin"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/ok" \
      --add-flags "$out/libexec/openknowledge/cli/dist/cli.mjs"
    ln -s ok "$out/bin/open-knowledge"
    installSkill "$out/libexec/openknowledge/cli/dist/assets/skills/discovery" openknowledge

    appDir="$desktop/libexec/openknowledge/desktop"
    pnpm --filter @inkeep/open-knowledge-desktop deploy --prod --offline --ignore-scripts "$appDir"
    cp -R packages/desktop/out "$appDir/"
    install -Dm644 packages/desktop/build/icon.png "$appDir/build/icon.png"
    mkdir -p "$appDir/resources" "$desktop/bin"
    ln -s "$out/libexec/openknowledge/cli/dist/public" "$appDir/resources/app"
    # Replace the deployed installer shims with the Nix CLI the patched app expects.
    rm -r "$appDir/resources/cli"
    ln -s "$out/libexec/openknowledge/cli" "$appDir/resources/cli"
    cp -R packages/app/src/locales "$appDir/resources/locales"

    makeWrapper ${lib.getExe electron} "$desktop/bin/openknowledge-desktop" \
      --add-flags "$appDir" \
      --set OK_NIX_RESOURCES "$appDir/resources" \
      --set OK_NIX_CLI "$out/bin/open-knowledge" \
      --set OK_NIX_NODE ${lib.getExe nodejs_24} \
      --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]} \
      --inherit-argv0

    install -Dm644 packages/desktop/build/icon.png "$desktop/share/icons/hicolor/512x512/apps/openknowledge.png"
    cp -r ${desktopItem}/share/applications "$desktop/share/"

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      find "$desktop/libexec/openknowledge" -path '*/node-pty/prebuilds/darwin-*/spawn-helper' -exec chmod 755 {} +

      bundle="$desktop/Applications/${appName}.app/Contents"
      mkdir -p "$bundle/MacOS" "$bundle/Resources"
      install -Dm644 ${infoPlist} "$bundle/Info.plist"
      png2icns "$bundle/Resources/openknowledge.icns" packages/desktop/build/icon.png
      ln -s "$desktop/bin/openknowledge-desktop" "$bundle/MacOS/${appName}"
    ''}

    runHook postInstall
  '';

  # Deploy can include foreign-platform prebuilds. Patch only the host natives.
  dontAutoPatchelf = true;
  dontStrip = true;
  dontPatchELF = true;
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    while IFS= read -r -d "" native; do
      autoPatchelf "$native"
    done < <(find "$out" "$desktop" -name '*.node' -path '*linux-${stdenv.hostPlatform.node.arch}*' -print0)
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = [ "--version" ];
  postInstallCheck = ''
    test -f "$out/share/skills/openknowledge/discovery/SKILL.md"
    ${lib.getExe nodejs_24} -e "require('$out/libexec/openknowledge/cli/dist/native/index.js').parseTomlToJson('x = 1')"

    ELECTRON_RUN_AS_NODE=1 ${lib.getExe electron} - "$desktop/libexec/openknowledge/desktop" <<'JS'
    const load = require('node:module').createRequire(process.argv[2] + '/package.json');
    for (const name of ['@inkeep/open-knowledge-core', '@inkeep/open-knowledge-server',
      '@inkeep/open-knowledge-native-config', '@napi-rs/keyring', '@parcel/watcher', 'node-pty']) load(name);
    JS
    test -f "$desktop/libexec/openknowledge/desktop/resources/app/index.html"
    test -f "$desktop/libexec/openknowledge/desktop/resources/cli/dist/cli.mjs"
  '';

  passthru = {
    inherit appName;
  };

  meta = {
    description = "Local-first Markdown knowledge base with agent integrations";
    homepage = "https://openknowledge.ai";
    changelog = "https://github.com/inkeep/open-knowledge/releases/tag/v${version}";
    license = lib.licenses.gpl3Plus;
    mainProgram = "ok";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
}
