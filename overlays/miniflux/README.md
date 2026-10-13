# Miniflux integration patches

These are local integration requirements, not a claim that an upstream fix is
pending. The pinned package is 2.3.3. Upstream's `internal/template/functions.go`
and `internal/integration/webhook/webhook.go` still expose only the `html url`
Trusted Types policies and `new_entries`/`save_entry` events at this review.

- `allow-highlight-trusted-type.patch` permits the `miniflux-highlight` policy
  used by `machines/malt/modules/miniflux/custom.js`. Remove it when that consumer
  no longer needs the policy or upstream provides a compatible policy extension.
- `send-webhook-on-star.patch` emits `star_entry` for newly starred entries from
  both API and UI actions. Preserve the distinct event contract; `save_entry`
  is not equivalent. Remove it only after consumers migrate to an upstream
  equivalent or the integration is retired.

The webhook patch's local history includes `183cf860` and `7ac1cdd9`, which adapt
it to upstream source changes. These raw diffs have no author header; do not
invent upstream authorship. Generate any new changes as separate format-patches
from the pinned source with these patches applied.

Upstream source: <https://github.com/miniflux/v2>. The Trusted Types policy change
in upstream PR #3727 is related context, not an implementation of the custom
highlight policy. Searches for star webhooks and Trusted Types did not establish
an upstream replacement for these local contracts.
