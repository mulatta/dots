{
  rsshub,
  applyPatches,
  fetchPnpmDeps,
  pnpm_10,
}:

rsshub.overrideAttrs (
  old:
  let
    patchedSrc = applyPatches {
      src = old.src;
      patches = [ ./patches/add-playwright-extra.patch ];
    };
  in
  {
    src = patchedSrc;

    pnpmDeps = fetchPnpmDeps {
      pname = old.pname;
      version = old.version;
      src = patchedSrc;
      fetcherVersion = 3;
      hash = "sha256-OMRIZmfV0o1wfiTQUL3ReJ/jIjTGwV4Lp8pVECk6tMQ=";
      pnpm = pnpm_10;
    };

    postPatch = (old.postPatch or "") + ''
      cp -R --no-preserve=mode ${./routes}/. lib/routes/
      find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.mts' -o -name '*.test.mtsx' \) -delete
      mkdir -p lib/custom-tests
      cp -R ${./tests}/. lib/custom-tests/
    '';
  }
)
