{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = {
    treefmt = {
      # Used to find the project root
      projectRootFile = ".git/config";

      programs.keep-sorted.enable = true;
      programs.terraform.enable = true;
      programs.yamlfmt.enable = true;
      programs.deadnix.enable = true;
      programs.nixfmt.enable = true;
      programs.shfmt.enable = true;

      programs.shellcheck.enable = true;
      settings.formatter = {
        shellcheck.options = [
          "--external-sources"
          "--source-path=SCRIPTDIR"
        ];
      };

      settings.global.excludes = [
        "**/secrets.yaml"
        "**/secrets.yml"
      ];
    };
  };
}
