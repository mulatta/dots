{ inputs, ... }:
{
  flake.overlays = {
    default = _final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev) system;
        config = prev.config;
      };
    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          (_final: prev: {
            unstable = import inputs.nixpkgs-unstable {
              inherit system;
              config = prev.config;
            };
          })
        ];
      };
    };
}
