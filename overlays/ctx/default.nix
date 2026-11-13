{ inputs }:
final: _prev: {
  ctx = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.ctx.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # ctx rejects provider history on ZFS as an unqualified filesystem, so
      # nothing under the ZFS home on citra is importable.
      # https://github.com/ctxrs/ctx/pull/1185
      (final.fetchpatch {
        name = "ctx-qualify-zfs-source-roots.patch";
        url = "https://github.com/ctxrs/ctx/commit/14dd6a6bb320805af9e6e76a8b32ff70ac6769dd.patch";
        hash = "sha256-tt+tsDWsS4QeBcocEHj7qbO3wxawDzNJQZNy0a+Jo6Y=";
      })
    ];
  });
}
