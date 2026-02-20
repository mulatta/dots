{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.file.".claude/skills".source = "${inputs.skillz}/skills";

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
      inputs.rag.packages.${system}.crwl
      inputs.rag.packages.${system}.pqa
      inputs.skillz.packages.${system}.context7-cli
      inputs.skillz.packages.${system}.crwl-cli
      inputs.skillz.packages.${system}.pareto-decide
      inputs.skillz.packages.${system}.style-review
    ];
}
