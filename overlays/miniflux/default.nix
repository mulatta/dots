_final: prev: {
  # custom.js needs a named Trusted Types policy upstream 2.3.5 lacks; see README.md.
  miniflux = prev.miniflux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./allow-highlight-trusted-type.patch
    ];
  });
}
