{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, lib, ... }:
    let
      # Stow commands have no extension; select by interpreter, not filename.
      scripts = builtins.readDir ../home/bin;
      scriptsFor =
        interpreters:
        lib.mapAttrsToList (name: _: "home/bin/${name}") (
          lib.filterAttrs (
            name: type:
            type == "regular"
            && builtins.elem (builtins.head (
              lib.splitString "\n" (builtins.readFile (../home/bin + "/${name}"))
            )) interpreters
          ) scripts
        );
      pythonScripts = scriptsFor [ "#!/usr/bin/env python3" ];
      shellScripts = scriptsFor [
        "#!/usr/bin/env bash"
        "#!/bin/sh"
      ];
    in
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

        # Limit source formatting to maintained integrations; YAML uses yamlfmt.
        programs.prettier = {
          enable = true;
          includes = [
            "*.json"
            "*.jsonc"
            "*.md"
            "*.markdown"
            "packages/**/*.ts"
            "packages/**/*.mjs"
            "machines/**/*.js"
            "machines/**/*.css"
          ];
        };

        settings.formatter = {
          ruff-format.includes = pythonScripts;
          shfmt.includes = shellScripts;
          shellcheck.includes = shellScripts;
          shellcheck.options = [
            "--external-sources"
            "--source-path=SCRIPTDIR"
          ];

          # ruff-isort: organize imports before ruff-format.
          ruff-isort = {
            command = lib.getExe pkgs.ruff;
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
            ]
            ++ pythonScripts;
            priority = 1; # run before ruff format
          };
        };

        settings.global.excludes = [
          "**/.direnv/**"
          "**/secrets.yaml"
          "**/secrets.yml"
          # Chromium's vendored OSC 52 helper retains its upstream shell style.
          "home/bin/osc52"
          # pi rewrites this on every run with its own style
          "home/.pi/**"
          # vendored pnpm lockfiles are generated; yamlfmt churns them
          "**/pnpm-lock.yaml"
        ];
      };
    };
}
