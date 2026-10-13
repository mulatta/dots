_final: prev: {
  # Local integrations need a named Trusted Types policy and star_entry webhooks,
  # neither provided by upstream 2.3.3. See README.md for consumers and removal criteria.
  miniflux = prev.miniflux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./allow-highlight-trusted-type.patch
      ./send-webhook-on-star.patch
    ];
  });
}
