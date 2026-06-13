{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        # Worktrees use a .git file, so anchor formatting on the flake root.
        projectRootFile = "flake.nix";

        programs.keep-sorted.enable = true;
        programs.terraform.enable = true;
        programs.yamlfmt.enable = true;
        programs.deadnix.enable = true;
        programs.nixfmt.enable = true;
        programs.ruff-format.enable = true;
        programs.shfmt.enable = true;
        programs.taplo = {
          enable = true;
          excludes = [
            "**/.direnv/**"
            "**/result/**"
          ];
        };
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

          # ruff-isort: organize imports before ruff-format.
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
          "**/.direnv/**"
          "**/secrets.yaml"
          "**/secrets.yml"
          # pi rewrites this on every run with its own style
          "home/.pi/**"
          # vendored pnpm lockfiles are generated; yamlfmt churns them
          "**/pnpm-lock.yaml"
        ];
      };
    };
}
