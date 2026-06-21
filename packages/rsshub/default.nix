{
  rsshub,
}:

# Drop the custom journal routes (Cell Press, Science, Nature, ...) into
# upstream rsshub. The routes drive a headless browser through patchright,
# which rsshub already ships as its own dependency, so no package.json or
# lockfile surgery is needed - we reuse upstream's src and pnpmDeps verbatim
# and only graft in the route sources.
rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R --no-preserve=mode ${./routes}/. lib/routes/
    find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.mts' -o -name '*.test.mtsx' \) -delete
    mkdir -p lib/custom-tests
    cp -R ${./tests}/. lib/custom-tests/
  '';
})
