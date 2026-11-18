_final: prev: {
  # Backport NixOS/nixpkgs#584912 while keeping this deployment's system pin.
  # Updating the entire input would change unrelated production services.
  # Remove after the pinned rustfs expression includes these dependencies.
  rustfs = prev.rustfs.overrideAttrs (old: {
    nativeBuildInputs =
      builtins.filter (input: input != prev.cacert) (old.nativeBuildInputs or [ ])
      ++ [
        prev.pkg-config
      ];
    buildInputs = (old.buildInputs or [ ]) ++ [
      prev.zstd
      prev.aws-lc
    ];
  });
}
