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
in
{
  home.file.".claude/skills".source = "${inputs.skillz}/skills";

  home.packages =
    (with llmAgentsPkgs; [
      gemini-cli
      ccstatusline
      ck
      qmd
    ])
    ++ (with self.packages.${system}; [
      claude-code
      claude-md
    ])
    ++ [
      inputs.skillz.packages.${system}.collect-github-reviews
    ];
}
