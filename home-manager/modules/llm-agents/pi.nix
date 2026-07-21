{
  lib,
  pkgs,
  llmAgents,
  ...
}:
let
  inherit (llmAgents) aiPkgs;
  pi-ext = llmAgents.pi-agent-extensions;
  piAgentDeps = pkgs.callPackage ../../../home/.pi/agent/default.nix { };
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

  home.activation.piAgentNodeModules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    agent_package="$HOME/.pi/agent/package.json"
    if [ ! -e "$agent_package" ]; then
      echo "pi: skipping node_modules link; $agent_package does not exist" >&2
    else
      agent_dir="$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/readlink -f "$agent_package")")"
      node_modules="$agent_dir/node_modules"
      if [ -e "$node_modules" ] && [ ! -L "$node_modules" ]; then
        echo "pi: refusing to replace non-symlink $node_modules" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/ln -sfnT ${piAgentDeps}/node_modules "$node_modules"
    fi
  '';

  home.packages = [
    (pkgs.writeShellScriptBin "pi" ''
      ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
      exec ${aiPkgs.pi}/bin/pi "$@"
    '')
  ];
}
