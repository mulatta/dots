{
  rsshub,
}:

rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R --no-preserve=mode ${./routes}/. lib/routes/
    find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.mts' -o -name '*.test.mtsx' \) -delete
  '';
})
