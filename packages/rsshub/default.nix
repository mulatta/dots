{ rsshub }:

rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R ${./routes}/. lib/routes/
    mkdir -p lib/custom-tests
    cp -R ${./tests}/. lib/custom-tests/
  '';
})
