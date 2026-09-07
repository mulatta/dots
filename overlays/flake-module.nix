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

      # The auth-source CLI accepts an OIDC secret only as an argument value, so
      # every reconciliation would publish it in the process listing. Give the
      # existing flag an environment source until go-gitea/gitea#36996 lands a
      # file-based option upstream.
      gitea = prev.gitea.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/gitea/oidc-secret-env.patch
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
