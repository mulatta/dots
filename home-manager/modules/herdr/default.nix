{
  inputs,
  self,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.herdr;
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = inputs.llm-agents.packages.${system};

  # herdr 0.7.5 drops kitty-protocol printable key release events (#1746).
  # Linux builds the fixed master commit until the next release; Darwin uses the
  # upstream binary and fetches source assets separately because the package src
  # is the binary artifact.
  fixedHerdr =
    if pkgs.stdenv.isDarwin then
      aiPkgs.herdr
    else
      aiPkgs.herdr.overrideAttrs (_old: rec {
        version = "0.7.5-unstable-2026-07-23";
        src = pkgs.fetchFromGitHub {
          owner = "ogulcancelik";
          repo = "herdr";
          rev = "e7fc85bfdb51f89488430adbfe5bbced3be79c2f";
          hash = "sha256-m5jEDImymgu84HXgeeLjOz6KhWP5+is8RNA5Ww+z5BI=";
        };
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit src;
          name = "herdr-${version}-vendor";
          hash = "sha256-lWnc0Ka0hp7bbm+dkKKj22Dbk+Cwrld86romXs3lzBs=";
        };
        # versionCheckHook compares against the pre-release Cargo version.
        doInstallCheck = false;
      });

  herdrSource =
    if pkgs.stdenv.isDarwin then
      pkgs.fetchFromGitHub {
        owner = "ogulcancelik";
        repo = "herdr";
        tag = "v0.7.5";
        hash = "sha256-3BA8eredGku+vsL2Af7sUf43QiArR5XTHNrI+X11vFM=";
      }
    else
      cfg.package.src;

  registry = pkgs.runCommand "herdr-plugins.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./registry.py} ${lib.escapeShellArgs (map toString cfg.plugins)} > $out
  '';
in
{
  disabledModules = [ "programs/herdr.nix" ];

  options.programs.herdr = {
    enable = lib.mkEnableOption "herdr, terminal workspace manager for AI agents";
    package = lib.mkOption {
      type = lib.types.package;
      default = fixedHerdr;
      description = "herdr package to install.";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        self.packages.${system}.herdr-autoname
        self.packages.${system}.herdr-sesh
      ];
      description = "herdr plugins to register declaratively.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.file.".claude/skills/herdr/SKILL.md".source = "${herdrSource}/SKILL.md";
    home.file.".pi/agent/extensions/herdr-agent-state.ts".source =
      "${herdrSource}/src/integration/assets/pi/herdr-agent-state.ts";
    home.file.".config/herdr/autoname-hook.zsh".source = "${
      self.packages.${system}.herdr-autoname
    }/shell/hook.zsh";

    home.activation.herdrPluginRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run install -Dm644 ${registry} "$HOME/.config/herdr/plugins.json"
    '';
  };
}
