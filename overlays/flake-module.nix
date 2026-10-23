{
  inputs,
  ...
}:
{
  flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
    (import ./miniflux)
    (import ./gitea)
    (import ./radicle-httpd)
    (import ./go-mockery)
    (import ./atuin)
    (import ./afew)
    (import ./php)
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
