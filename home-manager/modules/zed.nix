{
  inputs,
  self,
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
    self.packages.${system}.pi-acp
  ];

  programs.zed-editor.enable = true;
}
