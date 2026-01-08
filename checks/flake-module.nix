{ self, ... }:
{
  perSystem =
    {
      lib,
      system,
      ...
    }:
    {
      checks =
        let
          # System configuration checks (filter by current system)
          nixosChecks =
            lib.mapAttrs' (name: cfg: lib.nameValuePair "nixos-${name}" cfg.config.system.build.toplevel)
              (
                lib.filterAttrs (_: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) (
                  self.nixosConfigurations or { }
                )
              );

          darwinChecks = lib.mapAttrs' (name: cfg: lib.nameValuePair "darwin-${name}" cfg.system) (
            lib.filterAttrs (_: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) (
              self.darwinConfigurations or { }
            )
          );
        in
        nixosChecks // darwinChecks;
    };
}
