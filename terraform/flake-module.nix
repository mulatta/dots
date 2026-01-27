{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devShells.terraform = pkgs.mkShellNoCC {
        packages = [
          pkgs.sops
          pkgs.terragrunt
          pkgs.hurl
          pkgs.jq
          pkgs.yq-go
          pkgs.just
          pkgs.vultr-cli
          pkgs.wrangler
          pkgs.jtbl
          pkgs.glow
          config.packages.terraform
        ];
      };

      packages.terraform = pkgs.opentofu.withPlugins (p: [
        p.cloudflare_cloudflare
        p.integrations_github
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
