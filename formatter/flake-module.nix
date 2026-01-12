{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        # Used to find the project root
        projectRootFile = ".git/config";

        programs.keep-sorted.enable = true;
        programs.terraform.enable = true;
        programs.yamlfmt.enable = true;
        programs.deadnix.enable = true;
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        programs.taplo.enable = true;
        programs.rustfmt.enable = true;
        programs.shellcheck.enable = true;

        # prettier: json, markdown only (yaml uses yamlfmt)
        programs.prettier = {
          enable = true;
          includes = [
            "*.json"
            "*.jsonc"
            "*.md"
            "*.markdown"
          ];
        };

        settings.formatter = {
          shellcheck.options = [
            "--external-sources"
            "--source-path=SCRIPTDIR"
          ];

          # ruff-isort: organize imports (runs before ruff format)
          ruff-isort = {
            command = pkgs.ruff;
            options = [
              "check"
              "--fix"
              "--select"
              "I"
              "--unsafe-fixes"
            ];
            includes = [
              "*.py"
              "*.pyi"
            ];
            priority = 1; # run before ruff format
          };
        };

        settings.global.excludes = [
          "**/secrets.yaml"
          "**/secrets.yml"
        ];
      };
    };
}
