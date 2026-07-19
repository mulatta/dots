{
  pkgs,
  llmAgents,
  ...
}:
let
  inherit (llmAgents) aiPkgs;
  pi-ext = llmAgents.pi-agent-extensions;
  piAgentDeps = pkgs.callPackage ../../../home/.pi/agent/default.nix { };
  nostorePreload = pkgs.nostore-preload;
  nostoreEnvVar = nostorePreload.passthru.envVar;
  nostoreLib = "${nostorePreload}/lib/libnostore${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
in
{
  home.file.".pi/agent/extensions/direnv.ts".source = "${pi-ext}/direnv/index.ts";
  home.file.".pi/agent/extensions/questionnaire.ts".source = "${pi-ext}/questionnaire/index.ts";
  home.file.".pi/agent/extensions/slow-mode.ts".source = "${pi-ext}/slow-mode/index.ts";
  home.file.".pi/agent/extensions/notify.ts".source = "${pi-ext}/notify/index.ts";
  home.file.".pi/agent/extensions/permission-gate".source = "${pi-ext}/permission-gate";
  home.file.".pi/agent/extensions/stash".source = "${pi-ext}/stash";
  home.file.".pi/agent/extensions/statusline".source = "${pi-ext}/statusline";

  home.packages = [
    (pkgs.writeShellScriptBin "pi" ''
      # Block readdir(/nix/store) for the agent and its children; exported
      # before pueued so queued tasks inherit it too.
      export ${nostoreEnvVar}="${nostoreLib}''${${nostoreEnvVar}:+:${"$"}${nostoreEnvVar}}"
      ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
      # Extensions are symlinked from dotfiles, so node walk-up misses
      # their npm deps. NODE_PATH points jiti at the prebuilt node_modules.
      export NODE_PATH="${piAgentDeps}/node_modules''${NODE_PATH:+:$NODE_PATH}"
      exec ${aiPkgs.pi}/bin/pi "$@"
    '')
  ];
}
