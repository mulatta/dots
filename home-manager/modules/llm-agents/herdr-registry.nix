{
  pkgs,
  lib,
  selfPkgs,
  ...
}:
let
  plugins = [
    selfPkgs.herdr-autoname
    selfPkgs.herdr-pluck
    selfPkgs.herdr-sesh
  ];
  registry = pkgs.runCommand "herdr-plugins.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./herdr-registry.py} ${lib.escapeShellArgs (map toString plugins)} > $out
  '';
in
{
  home.activation.herdrPluginRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -Dm644 ${registry} "$HOME/.config/herdr/plugins.json"
  '';
}
