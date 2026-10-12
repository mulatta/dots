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
          nixosMachines =
            lib.mapAttrs' (name: cfg: lib.nameValuePair "nixos-${name}" cfg.config.system.build.toplevel)
              (
                lib.filterAttrs (_: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) (
                  self.nixosConfigurations or { }
                )
              );

          darwinMachines = lib.mapAttrs' (name: cfg: lib.nameValuePair "darwin-${name}" cfg.system) (
            lib.filterAttrs (_: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) (
              self.darwinConfigurations or { }
            )
          );

          # Home-manager configuration checks
          homeConfigurations = lib.mapAttrs' (
            name: cfg: lib.nameValuePair "home-manager-${name}" cfg.activationPackage
          ) (config.legacyPackages.homeConfigurations or { });

          # Build local packages even when no system or home profile uses them.
          packages = lib.mapAttrs' (name: lib.nameValuePair "package-${name}") config.packages;
          packageTests = lib.concatMapAttrs (
            name: pkg: lib.mapAttrs' (test: lib.nameValuePair "package-${name}-test-${test}") (pkg.tests or { })
          ) config.packages;
          devShells = lib.mapAttrs' (name: lib.nameValuePair "devShell-${name}") config.devShells;

          # NixOS module VM tests only run on Linux.
          nixosModules = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
            lib.mapAttrs' (name: lib.nameValuePair "nixosModule-${name}") {
              agentgateway = pkgs.callPackage ../nixosModules/agentgateway/test.nix { };
            }
          );

        in
        nixosMachines
        // darwinMachines
        // packages
        // packageTests
        // devShells
        // homeConfigurations
        // nixosModules;
    };
}
