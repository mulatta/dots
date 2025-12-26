{
  self,
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      homeManagerConfiguration =
        {
          extraModules ? [ ],
        }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              _module.args.self = self;
              _module.args.inputs = self.inputs;
              imports = extraModules ++ [
                inputs.sops-nix.homeManagerModules.sops
                inputs.nix-index-database.homeModules.nix-index
                { programs.nix-index-database.comma.enable = true; }
                inputs.stylix.homeModules.stylix
                inputs.catppuccin.homeModules.catppuccin
              ];
            }
          ];
        };

      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      legacyPackages.homeConfigurations = {
        base = homeManagerConfiguration {
          extraModules = [ ./profiles/base.nix ];
        };
      }
      // lib.optionalAttrs (system == "aarch64-darwin") {
        macos = homeManagerConfiguration {
          extraModules = [ ./profiles/macos.nix ];
        };
        "seungwon@rhesus" = homeManagerConfiguration {
          extraModules = [
            ./profiles/macos.nix
            ./machines/rhesus.nix
          ];
        };
      }
      // lib.optionalAttrs (system == "aarch64-linux") {
        desktop = homeManagerConfiguration {
          extraModules = [ ./profiles/desktop.nix ];
        };
        "seungwon@mulatta" = homeManagerConfiguration {
          extraModules = [
            ./profiles/desktop.nix
            ./machines/mulatta.nix
          ];
        };
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        desktop = homeManagerConfiguration {
          extraModules = [ ./profiles/desktop.nix ];
        };
        "seungwon@psi" = homeManagerConfiguration {
          extraModules = [
            ./profiles/base.nix
            ./machines/psi.nix
            inputs.vscode-server.homeModules.default
          ];
        };
      };
    };
}
