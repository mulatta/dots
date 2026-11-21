# Miniflux integration patch

This is a local integration requirement, not a claim that an upstream fix is
pending. The pinned package is 2.3.3. Upstream's `internal/template/functions.go`
still exposes only the `html url` Trusted Types policies at this review.

- `allow-highlight-trusted-type.patch` permits the `miniflux-highlight` policy
  used by `machines/malt/modules/miniflux/custom.js`. Remove it when that consumer
  no longer needs the policy or upstream provides a compatible policy extension.

Upstream source: <https://github.com/miniflux/v2>. The Trusted Types policy change
in upstream PR #3727 is related context, not an implementation of the custom
highlight policy. Searches for Trusted Types did not establish an upstream
replacement for this local contract.
