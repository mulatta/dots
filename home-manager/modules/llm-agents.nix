{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  pi-ext = inputs.pi-agent-extensions;
in
{
  home.file.".claude/skills".source = "${inputs.skillz}/skills";
  home.file.".pi/agent/extensions/direnv.ts".source = "${pi-ext}/direnv/index.ts";
  home.file.".pi/agent/extensions/questionnaire.ts".source = "${pi-ext}/questionnaire/index.ts";
  home.file.".pi/agent/extensions/slow-mode.ts".source = "${pi-ext}/slow-mode/index.ts";

  home.packages =
    (with pkgs; [
      claude-code # custom wrapper (dots overlay)
      claude-md # dots overlay
      pueue
      qmd # dots overlay (for CUDA override chain)
    ])
    ++ [
      inputs.llm-agents.packages.${system}.ccstatusline
      inputs.llm-agents.packages.${system}.ck
      inputs.llm-agents.packages.${system}.gemini-cli
      inputs.llm-agents.packages.${system}.workmux
      inputs.llm-agents.packages.${system}.tuicr
      (pkgs.writeShellScriptBin "pi" ''
        ${pkgs.pueue}/bin/pueued -d 2>/dev/null || true
        exec ${inputs.llm-agents.packages.${system}.pi}/bin/pi "$@"
      '')
      inputs.rag.packages.${system}.crwl
      inputs.rag.packages.${system}.pqa
      inputs.skillz.packages.${system}.context7-cli
      inputs.skillz.packages.${system}.crwl-cli
      inputs.skillz.packages.${system}.pareto-decide
      inputs.skillz.packages.${system}.pexpect-cli
      inputs.skillz.packages.${system}.style-review
    ];
}
