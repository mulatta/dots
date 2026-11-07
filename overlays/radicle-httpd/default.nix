final: prev: {
  # tar.zst archive downloads shell out to zstd, which nixpkgs leaves off PATH.
  radicle-httpd = prev.radicle-httpd.overrideAttrs (old: {
    nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ final.zstd ];
    postFixup = (old.postFixup or "") + ''
      for program in $out/bin/*; do
        wrapProgram "$program" --prefix PATH : ${prev.lib.makeBinPath [ final.zstd ]}
      done
    '';
  });
}
