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
  imagemagick,
  python3,
  rcodesign,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  pname = "openknowledge";
  version = "0.85.0";
  pnpm = pnpm_12;
  electron = electron_44;
  appName = "OpenKnowledge";

  src = fetchFromGitHub {
    owner = "inkeep";
    repo = "open-knowledge";
    tag = "v${version}";
    hash = "sha256-ArVBXvLxw9c5onQw5+5dnU/Rk9kkc1z3s+NU+L3zylM=";
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
      CFBundleDisplayName = appName;
      CFBundleVersion = version;
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
      hash = "sha256-6FfyCNIO18UQSPPISG1GdUq6ql/899uwdMwmh28/fy4=";
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
    # These repeated expressions move independently as upstream splits index.ts.
    # Match only renderer/devtools policy, never globally replace app.isPackaged:
    # installer, uninstaller and platform behavior still need its real value.
    substituteInPlace packages/desktop/src/main/index.ts \
      --replace-fail "const rendererEntryPath = app.isPackaged" "const rendererEntryPath = isProductionRuntime" \
      --replace-fail "rendererEntryPath: app.isPackaged" "rendererEntryPath: isProductionRuntime" \
      --replace-fail "join(process.resourcesPath, 'app', 'index.html')" "join(runtimeResources, 'app', 'index.html')" \
      --replace-fail "!app.isPackaged || DESKTOP_VARIANT.name !== 'stable'" "!isProductionRuntime || DESKTOP_VARIANT.name !== 'stable'"

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
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    libicns
    imagemagick
    python3
    rcodesign
  ]
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
    # Use the already locked smol-toml dependency to preserve the toolchain
    # table while selecting Nix's compiler, regardless of upstream's version.
    cp ${./pin-rust-toolchain.mjs} scripts/nix-rust-toolchain.mjs
    node scripts/nix-rust-toolchain.mjs rust-toolchain.toml ${rustc.version}

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

  postBuild = ''
    cp ${./nix-policy.test.ts} packages/desktop/tests/main/nix-policy.test.ts
    pnpm --dir packages/desktop exec vitest run tests/main/nix-policy.test.ts
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
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Upstream artwork fills the canvas; macOS icons need an outer inset.
      # Electron also loads this PNG for app.dock.setIcon in our unpackaged runtime.
      magick packages/desktop/build/icon.png -resize 832x832 \
        -gravity center -background none -extent 1024x1024 \
        packages/desktop/build/icon.png
    ''}
    install -Dm644 packages/desktop/build/icon.png "$appDir/build/icon.png"
    mkdir -p "$appDir/resources" "$desktop/bin"
    ln -s "$out/libexec/openknowledge/cli/dist/public" "$appDir/resources/app"
    # Replace the deployed installer shims with the Nix CLI the patched app expects.
    rm -r "$appDir/resources/cli"
    ln -s "$out/libexec/openknowledge/cli" "$appDir/resources/cli"
    cp -R packages/app/src/locales "$appDir/resources/locales"

    electronExecutable=${lib.getExe electron}
    launcher="$desktop/bin/openknowledge-desktop"
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        bundle="$desktop/Applications/${appName}.app/Contents"
        mkdir -p "$(dirname "$bundle")"
        cp -R ${electron}/Applications/Electron.app/Contents "$bundle"
        chmod -R u+w "$bundle"

        # Preserve Electron's Cocoa configuration and privacy usage descriptions.
        python3 - "$bundle/Info.plist" ${infoPlist} <<'PY'
      import plistlib
      import sys
      from pathlib import Path

      path, overrides = sys.argv[1:]
      with open(path, "rb") as source:
          info = plistlib.load(source)
      with open(overrides, "rb") as source:
          info.update(plistlib.load(source))
      with open(path, "wb") as destination:
          plistlib.dump(info, destination)

      # Nix Electron omits helper executable keys; bundle signing needs them.
      for helper in (Path(path).parent / "Frameworks").glob("Electron Helper*.app"):
          contents = helper / "Contents"
          executable, = (contents / "MacOS").iterdir()
          helper_plist = contents / "Info.plist"
          with helper_plist.open("rb") as source:
              helper_info = plistlib.load(source)
          helper_info["CFBundleExecutable"] = executable.name
          with helper_plist.open("wb") as destination:
              plistlib.dump(helper_info, destination)
      PY
        png2icns "$bundle/Resources/openknowledge.icns" packages/desktop/build/icon.png
        electronExecutable="$bundle/MacOS/Electron"
        launcher="$bundle/MacOS/${appName}"
        ln -s "../Applications/${appName}.app/Contents/MacOS/${appName}" "$desktop/bin/openknowledge-desktop"
    ''}

    # Passing the app directory keeps Electron's default-app bootstrap and
    # isPackaged=false, avoiding upstream mutable installer behavior on macOS.
    makeWrapper "$electronExecutable" "$launcher" \
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
    ''}

    runHook postInstall
  '';

  # Deploy can include foreign-platform prebuilds. Patch only the host natives.
  dontAutoPatchelf = true;
  dontStrip = true;
  dontPatchELF = true;
  postFixup =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      while IFS= read -r -d "" native; do
        autoPatchelf "$native"
      done < <(find "$out" "$desktop" -name '*.node' -path '*linux-${stdenv.hostPlatform.node.arch}*' -print0)
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Metadata and launcher changes invalidate the original bundle seal.
      rcodesign sign --timestamp-url none "$desktop/Applications/${appName}.app"
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
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      icon="$desktop/libexec/openknowledge/desktop/build/icon.png"
      test "$(magick identify -format '%wx%h' "$icon")" = 1024x1024
      test "$(magick "$icon" -alpha extract -threshold 50% -format '%@' info:)" = 832x832+96+96
      bundle="$desktop/Applications/${appName}.app/Contents"
      test -s "$bundle/Resources/openknowledge.icns"
      test -x "$bundle/MacOS/${appName}"
      test -x "$bundle/MacOS/Electron"
      test ! -L "$bundle/MacOS/Electron"
      test -d "$bundle/Frameworks/Electron Framework.framework"
      ELECTRON_RUN_AS_NODE=1 "$bundle/MacOS/Electron" -e 'console.log(process.versions.electron)'
    ''}
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
