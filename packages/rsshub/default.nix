{ rsshub }:

rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp -R ${./routes}/. lib/routes/
  '';
})
