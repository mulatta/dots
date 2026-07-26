{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.herdr;
  registry = pkgs.runCommand "herdr-plugins.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./registry.py} ${lib.escapeShellArgs (map toString cfg.plugins)} > $out
  '';
in
{
  options.programs.herdr = {
    enable = lib.mkEnableOption "herdr, terminal workspace manager for AI agents";
    package = lib.mkOption {
      type = lib.types.package;
      description = "herdr package to install.";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "herdr plugins to register declaratively.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.activation.herdrPluginRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run install -Dm644 ${registry} "$HOME/.config/herdr/plugins.json"
    '';
  };
}
