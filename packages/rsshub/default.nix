{
  rsshub,
}:

# Graft custom routes (INU/KOSAF notices, GitHub trending) into upstream rsshub.
# These are plain-HTTP routes - no headless browser needed - so we reuse
# upstream's src and pnpmDeps verbatim and only add the route sources.
rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R --no-preserve=mode ${./routes}/. lib/routes/
    find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.mts' -o -name '*.test.mtsx' \) -delete
  '';
})
