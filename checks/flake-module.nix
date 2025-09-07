{
  perSystem =
    {
      self',
      lib,
      ...
    }:
    {
      checks =
        let
          devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") self'.devShells;
          packages = lib.mapAttrs' (n: lib.nameValuePair "packages-${n}") self'.packages;
        in
        { inherit (self') formatter; } // devShells // packages;
    };
}
