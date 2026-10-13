# Radicle patch provenance

The package is pinned to radicle-httpd 0.28.0 from Radicle repository
`z4V1sjrXqjvFdnCUbxPFqd5p4DtH5` on `seed.radicle.dev`.

The three patch headers identify Jörg Thalheim as their original author:

| Patch                 | Original commit                            |
| --------------------- | ------------------------------------------ |
| Search debounce       | `d682f1b19d15734b78af91e6fd7d81599dcd401b` |
| Zstd archives         | `034f9f34a03f8f23ab492826635fdeb83cdd9a3c` |
| Archive 404 responses | `1b20c2f1b2f7bfcccdfd624e6305fe6222d4d39b` |

Dots imported them in `f35fef13`. Local commit `00394df3` adapted the two archive
tests to the newer router signature by passing `Default::default()`. Those two
files are therefore adapted patches, not byte-identical exports of the original
commits. Preserve the original attribution and this adaptation record; new local
changes should use separate follow-up patches where practical.

Upstream master `68d7a335791e8f73ea313bc7582203c40728aecc` now implements
batched peer-event indexing, `.tar.zst` downloads, and unknown-archive-reference
404 responses under `explorer/crates/`. These are equivalent behaviors, not a
claim that the three original commits were merged unchanged. The latest release
advertised by the seed is still 0.28.0, whose source lacks these fixes, so the
pinned package still needs all three patches. Recheck the released source and
regression tests when updating; do not remove patches based on master alone.
