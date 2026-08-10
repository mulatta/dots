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

  # Package src is platform-dependent, so fetch release source for shared integration assets.
  herdrSource = pkgs.fetchFromGitHub {
    owner = "ogulcancelik";
    repo = "herdr";
    tag = "v${aiPkgs.herdr.version}";
    hash = "sha256-empFQ+hrnCh2JhOzQRWSCLV0YoZC3DXW3bY6k8YuJjk=";
  };

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
      default = aiPkgs.herdr;
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
    home.file.".claude/skills/herdr/SKILL.md".source = "${herdrSource}/skills/herdr/SKILL.md";
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
