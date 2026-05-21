{ rsshub }:

rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R --no-preserve=mode ${./routes}/. lib/routes/
    find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' \) -delete
    mkdir -p lib/custom-tests
    cp -R ${./tests}/. lib/custom-tests/
  '';
})
