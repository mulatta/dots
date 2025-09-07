# https://github.com/nix-community/infra/tree/e25c9f72a56641d5b4646d2711e59ccc63e171b8/dev/terraform.nix
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
          config.packages.terraform
        ];
      };

      packages.terraform = pkgs.opentofu.withPlugins (p: [
        p.github
        p.gitlab
        p.vultr
        p.sops
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
