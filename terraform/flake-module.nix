{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devShells.terraform = pkgs.mkShellNoCC {
        # Apply these to both direnv and `nix develop -c` entry points.
        TG_NON_INTERACTIVE = "true";
        TG_NO_AUTO_PROVIDER_CACHE_DIR = "1";
        TG_PROVIDER_CACHE = "false";
        TG_TF_PATH = "${config.packages.terraform}/bin/tofu";
        # Never silently reinitialize between a reviewed plan and apply.
        TG_NO_AUTO_INIT = "true";
        DOTS_TERRAFORM_GUARD = "${pkgs.writeShellScript "terraform-environment-guard" ''
          set -eu
          if [ "''${TG_TF_PATH:-}" != "${config.packages.terraform}/bin/tofu" ] ||
             [ ! -x "${config.packages.terraform}/bin/tofu" ]; then
            echo 'Use the Terraform devshell without overriding TG_TF_PATH.' >&2
            exit 1
          fi
          if [ -n "''${TF_PLUGIN_CACHE_DIR:-}" ] ||
             [ -n "''${TF_CLI_CONFIG_FILE:-}" ] ||
             [ "''${TG_PROVIDER_CACHE:-}" != false ] ||
             [ "''${TG_NO_AUTO_PROVIDER_CACHE_DIR:-}" != 1 ]; then
            echo 'External provider caches or CLI configuration are not supported.' >&2
            exit 1
          fi
          if [ "''${TG_NO_AUTO_INIT:-}" != true ]; then
            echo 'Automatic init is disabled; run an explicit init first.' >&2
            exit 1
          fi
        ''}";

        packages = [
          pkgs.sops
          pkgs.terragrunt
          pkgs.jq
          pkgs.yq-go
          pkgs.vultr-cli
          config.packages.terraform
        ];
      };

      packages.terraform = pkgs.opentofu.withPlugins (p: [
        p.cloudflare_cloudflare
        p.vultr_vultr
        p.carlpett_sops
        p.hashicorp_local
        p.hashicorp_null
      ]);

      packages.terraform-validate =
        pkgs.runCommand "terraform-validate"
          {
            buildInputs = [ config.packages.terraform ];
            files = pkgs.lib.fileset.toSource rec {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                root
              ];
            };
          }
          ''
            cp --no-preserve=mode -r $files/* .
            tofu init -upgrade -backend=false -input=false
            tofu validate
            touch $out
          '';
    };
}
