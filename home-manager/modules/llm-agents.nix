{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = with inputs.llm-agents.packages.${system}; [
    claude-code
  ];
}
