{ inputs, ... }:
{
  flake.overlays = {
    default =
      _final: prev:
      let
        unstable = import inputs.nixpkgs-unstable {
          system = prev.stdenv.hostPlatform.system;
          config = prev.config;
        };
      in
      {
        inherit unstable;
        zjstatus = inputs.zjstatus.packages.${prev.stdenv.hostPlatform.system}.default;

        # Use nixpkgs-unstable vaultwarden 1.35.1+ (SSO support added in 1.35.0)
        vaultwarden = unstable.vaultwarden;
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
