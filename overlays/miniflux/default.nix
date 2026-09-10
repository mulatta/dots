_final: prev: {
  miniflux = prev.miniflux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./allow-highlight-trusted-type.patch
      ./send-webhook-on-star.patch
    ];
  });
}
