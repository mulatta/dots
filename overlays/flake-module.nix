{
  inputs,
  ...
}:
{
  flake.overlays = {
    dots = _final: prev: {
      miniflux = prev.miniflux.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/miniflux/allow-highlight-trusted-type.patch
          ../packages/miniflux/send-webhook-on-star.patch
        ];
      });

    };
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
