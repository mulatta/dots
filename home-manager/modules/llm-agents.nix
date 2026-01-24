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
    ])
    ++ (with self.packages.${system}; [
      claude-code
      claude-md
    ]);
}
