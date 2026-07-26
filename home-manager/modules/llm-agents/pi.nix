{
  lib,
  pkgs,
  llmAgents,
  selfPkgs,
  ...
}:
let
  inherit (llmAgents) aiPkgs herdrPackage;
  pi-ext = llmAgents.pi-agent-extensions;
in
{
  home.file.".pi/agent/extensions/direnv.ts".source = "${pi-ext}/direnv/index.ts";
  home.file.".pi/agent/extensions/questionnaire.ts".source = "${pi-ext}/questionnaire/index.ts";
  home.file.".pi/agent/extensions/slow-mode.ts".source = "${pi-ext}/slow-mode/index.ts";
  home.file.".pi/agent/extensions/notify.ts".source = "${pi-ext}/notify/index.ts";
  home.file.".pi/agent/extensions/fetch".source = "${pi-ext}/fetch";
  home.file.".pi/agent/extensions/permission-gate".source = "${pi-ext}/permission-gate";
  home.file.".pi/agent/extensions/stash".source = "${pi-ext}/stash";
  home.file.".pi/agent/extensions/statusline".source = "${pi-ext}/statusline";

  # herdr reports agent state/session to panes through this Pi extension.
  home.file.".config/herdr/autoname-hook.zsh".source = "${selfPkgs.herdr-autoname}/shell/hook.zsh";

  home.file.".pi/agent/extensions/herdr-agent-state.ts" = lib.mkIf pkgs.stdenv.isLinux {
    source = "${herdrPackage.src}/src/integration/assets/pi/herdr-agent-state.ts";
  };

  home.packages = [
    (pkgs.writeShellScriptBin "pi" ''
      ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
      exec ${aiPkgs.pi}/bin/pi "$@"
    '')
  ];
}
