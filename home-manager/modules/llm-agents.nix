{
  self,
  inputs,
  system,
  ...
}:
{
  home.packages =
    (with inputs.llm-agents.packages.${system}; [
      gemini-cli
      ccstatusline
      ck
    ])
    ++ (with self.packages.${system}; [
      claude-code
      claude-md
    ])
    ++ (with inputs.qmd.packages.${system}; [
      qmd
    ]);
}
