{
  buildNpmPackage,
  lib,
  callPackage,
  rhwp,
  stdenv,
}:

let
  filesAction = buildNpmPackage {
    pname = "rhwp-viewer-files-action";
    version = "0.1.0";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./app/src
        ./package-lock.json
        ./package.json
      ];
    };

    npmDepsHash = "sha256-rF6cxf8hfFwyzMPqzfOAgFQhOobxkwd86YMHi9pVtOg=";
    npmBuildScript = "build:files-action";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp app/js/files-action.js $out/files-action.js
      runHook postInstall
    '';
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rhwp-viewer";
  version = "0.1.0";

  # Nextcloud app id must stay alphanumeric (no dashes), distinct from pname.
  passthru = {
    appId = "rhwpviewer";
    tests = lib.optionalAttrs stdenv.hostPlatform.isLinux {
      nextcloud = callPackage ./tests/nixos-test.nix { rhwp-viewer = finalAttrs.finalPackage; };
    };
  };

  src = ./app;

  dontBuild = true;

  # `services.nextcloud.extraApps` symlinks $out into nix-apps/<appid>, so the
  # Nextcloud-expected layout (appinfo/, js/, bin/, ...) sits directly at $out.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/{js,bin}
    cp -r $src/appinfo $out/
    cp -r $src/lib $out/
    cp -r $src/templates $out/
    cp -r ${rhwp.studio}/* $out/js/

    # rhwp-studio is a Vite build serving from the domain root, so it emits
    # absolute asset references (`new URL(`/assets/...`, `url(/images/...`).
    # Nextcloud serves the app under a subpath, so rewrite them to relative.
    # Vite code-splits the bundle: only the app entry chunk carries these
    # references, while sibling chunks (e.g. canvaskit-renderer) have none, so
    # a blanket --replace-fail over the glob aborts on the chunks that never
    # had the anchor. Rewrite per-file where the anchor exists, and still fail
    # if it is absent from every file - that signals a real bundle-layout
    # change rather than an expected extra chunk.
    rewriteAnchor() {
      local from="$1" to="$2" rewrote=
      shift 2
      for f in "$@"; do
        if grep -qF "$from" "$f"; then
          substituteInPlace "$f" --replace-fail "$from" "$to"
          rewrote=1
        fi
      done
      [ -n "$rewrote" ] || {
        echo "rhwp-viewer: anchor '$from' not found in any chunk; studio bundle layout changed" >&2
        exit 1
      }
    }
    rewriteAnchor 'new URL(`/assets/' 'new URL(`./' $out/js/assets/*.js
    rewriteAnchor 'url(/images/' 'url(../images/' $out/js/assets/*.css

    cp -r $src/js/. $out/js/
    cp ${filesAction}/files-action.js $out/js/files-action.js
    cp ${lib.getExe rhwp} $out/bin/rhwp
    runHook postInstall
  '';

  meta = {
    description = "Nextcloud 33/34 app: open and edit HWP/HWPX files via rhwp WASM";
    license = lib.licenses.mit;
  };
})
