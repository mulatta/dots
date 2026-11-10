final: prev: {
  # nixpkgs' cargoSetupHook now links jemalloc from the system; drop once
  # NixOS/nixpkgs#586026 reaches nixos-unstable.
  stalwart_0_15 = prev.stalwart_0_15.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ final.rust-jemalloc-sys ];
  });
}
