{ inputs, ... }:
{
  flake.overlays = {
    default = _final: prev: {
      zjstatus = inputs.zjstatus.packages.${prev.stdenv.hostPlatform.system}.default;

      # afew: fix pkg_resources deprecation warning (PR #363 merged but not in 3.0.1)
      afew = prev.afew.overridePythonAttrs (old: {
        version = "3.0.2";
        src = prev.fetchFromGitHub {
          owner = "afewmail";
          repo = "afew";
          rev = "23b5aeaa43572a59e95fb00732292087b091d4a1";
          hash = "sha256-RClWSHvyDTJjJsjLXAIAv24TE5NskXLCQ7RcKKt2330=";
        };
        env.SETUPTOOLS_SCM_PRETEND_VERSION = "3.0.2";
        dependencies = (old.dependencies or [ ]) ++ [
          prev.python3Packages.notmuch2
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
          inputs.self.overlays.default
        ];
      };
    };
}
