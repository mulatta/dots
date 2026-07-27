{
  pkgs,
  llmAgents,
  ...
}:
let
  inherit (llmAgents) aiPkgs;
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

  home.packages = [
    (pkgs.writeShellScriptBin "pi" ''
      ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
      exec ${aiPkgs.pi}/bin/pi "$@"
    '')
  ];
}
