{ inputs, ... }:
{
  flake.overlays = {
    default = _final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev) system;
        config = prev.config;
      };
      zjstatus = inputs.zjstatus.packages.${prev.system}.default;
    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.self.overlays.default
        ];
      };
    };
}
