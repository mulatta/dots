{
  inputs,
  ...
}:
{
  flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
    (import ./miniflux)
    (import ./gitea)
    (import ./radicle-httpd)
  ];

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
