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
        # Only public repositories are mirrored, so unencrypted node traffic is accepted.
        config.permittedInsecurePackages = [ "radicle-node-1.10.3" ];
        overlays = [
          inputs.self.overlays.default
        ];
      };
    };
}
