{
  inputs,
  self,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [
    inputs.skillz.homeModules.default
    ./packages.nix
    ./pi.nix
    ./skills.nix
  ];

  _module.args.llmAgents = {
    inherit system;
    inherit (inputs) pi-agent-extensions;
    aiPkgs = inputs.llm-agents.packages.${system};
    skillzPkgs = inputs.skillz.packages.${system};
    claudeCode = self.packages.${system}.claude-code;
  };
}
