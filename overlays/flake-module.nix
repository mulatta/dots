{
  inputs,
  ...
}:
{
  flake.overlays.default = inputs.nixpkgs.lib.composeManyExtensions [
    (import ./miniflux)
    (import ./gitea)
    (import ./radicle-httpd)
    (import ./stalwart)
    (import ./weechat-matrix-rs)
    (import ./atuin)
    (import ./afew)
    (import ./hindsight { inherit inputs; })
    (import ./ctx { inherit inputs; })
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
