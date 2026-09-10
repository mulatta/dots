{
  inputs,
  ...
}:
{
  flake.overlays = {
    dots =
      final: prev:
      (import ./chatgpt { inherit inputs; } final prev)
      // (import ./miniflux final prev)
      // (import ./gitea final prev);
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.self.overlays.dots
        ];
      };
    };
}
