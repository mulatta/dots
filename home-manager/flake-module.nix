{
  self,
  inputs,
  ...
}:
let
  mkHome =
    system:
    {
      extraModules ? [ ],
    }:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
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
    });
in
{
  flake.homeConfigurations = {
    "seungwon@rhesus" = mkHome "aarch64-darwin" {
      extraModules = [ ./rhesus.nix ];
    };
    "seungwon@mulatta" = mkHome "aarch64-linux" {
      extraModules = [ ./mulatta.nix ];
    };
    "seungwon@psi" = mkHome "aarch64-linux" {
      extraModules = [ ./psi.nix ];
    };
  };
}
