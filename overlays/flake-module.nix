{ inputs, ... }:
{
  flake.overlays = {
    default = _final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config = prev.config;
      };
      zjstatus = inputs.zjstatus.packages.${prev.stdenv.hostPlatform.system}.default;
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
