{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
let
  # Use overlay version if available (from gpu-support.nix), otherwise fallback to inputs
  llmAgentsPkgs = pkgs.llm-agents or inputs.llm-agents.packages.${system};
  myPkgs = self.packages.${system};
  skillzPkgs = inputs.skillz.packages.${system};
in
{
  home.file.".claude/skills".source = "${inputs.skillz}/skills";

  home.packages = [
    llmAgentsPkgs.gemini-cli
    llmAgentsPkgs.ccstatusline
    llmAgentsPkgs.ck
    llmAgentsPkgs.qmd
    skillzPkgs.style-review
    myPkgs.claude-code
    myPkgs.claude-md
    pkgs.pueue
  ];
}
