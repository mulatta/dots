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

        in
        lib.mkMerge [
          (nixosMachines // darwinMachines // packages // packageTests // devShells // homeConfigurations)
          (lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            bulwark-webmail = pkgs.callPackage ../nixosModules/bulwark-webmail/test.nix { };
          })
        ];
    };
}
