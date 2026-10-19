{
  inputs,
  system,
  ...
}:
let
  aiPkgs = inputs.llm-agents.packages.${system};
in
{
  home.packages = [
    aiPkgs.claude-agent-acp
    aiPkgs.codex-acp
    aiPkgs.pi-acp
  ];

  programs.zed-editor.enable = true;
}
