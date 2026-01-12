{ self, ... }:
{
  perSystem =
    {
      config,
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

          # Home-manager configuration checks
          homeChecks = lib.mapAttrs' (
            name: cfg: lib.nameValuePair "home-manager-${name}" cfg.activationPackage
          ) (config.legacyPackages.homeConfigurations or { });
        in
        nixosChecks // darwinChecks // homeChecks;
    };
}
