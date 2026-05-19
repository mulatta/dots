{ self, ... }:
{
  perSystem =
    {
      config,
      lib,
      pkgs,
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

          moduleChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            bulwark-webmail = pkgs.callPackage ../nixosModules/bulwark-webmail/test.nix { };
            restate = pkgs.callPackage ../nixosModules/restate/test.nix { };
          };
        in
        nixosChecks // darwinChecks // homeChecks // moduleChecks;
    };
}
