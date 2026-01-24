{
  inputs,
  system,
  ...
}:
{
  home.packages = with inputs.llm-agents.packages.${system}; [
    claude-code
    gemini-cli
    ccstatusline
  ];
}
