final: prev: {
  # nixpkgs' cargoSetupHook now makes zstd-sys link the system zstd, which
  # the package does not list yet.
  weechat-matrix-rs = prev.weechat-matrix-rs.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ final.zstd ];
  });
}
