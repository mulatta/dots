{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  miniserve,
}:
let
  srcs = lib.importJSON ./srcs.json;
  # tests fail in sandbox: port binding conflicts (os error 48)
  miniserve' = miniserve.overrideAttrs { doCheck = false; };
in
buildNpmPackage {
  pname = "chartdb";
  version = srcs.version;

  src = fetchFromGitHub {
    owner = "chartdb";
    repo = "chartdb";
    rev = "v${srcs.version}";
    hash = srcs.srcHash;
  };

  npmDepsHash = srcs.npmDepsHash;

  nativeBuildInputs = [ makeWrapper ];

  # vite build runs lint + tsc first; skip lint in nix build
  buildPhase = ''
    runHook preBuild
    npx vite build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/chartdb $out/bin
    cp -r dist/* $out/share/chartdb/

    # Usage: chartdb [-p PORT] [miniserve-args...]
    # Default port 3000, overridable via -p flag
    cat > $out/bin/chartdb <<'WRAPPER'
    #!/usr/bin/env bash
    case "$1" in
      -h|--help)
        echo "Usage: chartdb [-p PORT] [miniserve-args...]"
        echo "Serve ChartDB locally (default: http://localhost:3000)"
        exit 0;;
    esac
    exec @miniserve@ --spa --index index.html -p 3000 "$@" @static@
    WRAPPER
    chmod +x $out/bin/chartdb
    substituteInPlace $out/bin/chartdb \
      --replace-fail @miniserve@ ${lib.getExe miniserve'} \
      --replace-fail @static@ $out/share/chartdb

    runHook postInstall
  '';

  meta = {
    description = "Database schema editor and visualization tool";
    homepage = "https://github.com/chartdb/chartdb";
    license = lib.licenses.agpl3Only;
    mainProgram = "chartdb";
  };
}
