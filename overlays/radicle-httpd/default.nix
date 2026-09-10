final: prev: {
  # Keep these downstream fixes until radicle-httpd releases event debouncing,
  # tar.zst archives, and 404 responses for unknown archive references.
  radicle-httpd = prev.radicle-httpd.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./radicle-search-debounce.patch
      ./radicle-httpd-zstd-archive.patch
      ./radicle-httpd-archive-404.patch
    ];
    nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ final.zstd ];
    postFixup = (old.postFixup or "") + ''
      for program in $out/bin/*; do
        wrapProgram "$program" --prefix PATH : ${prev.lib.makeBinPath [ final.zstd ]}
      done
    '';
  });
}
