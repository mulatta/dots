{
  inputs,
  self,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = inputs.llm-agents.packages.${system};
in
{
  imports = [
    inputs.skillz.homeModules.default
    ./packages.nix
    ./pi.nix
    ./skills.nix
    ../herdr
  ];

  programs.herdr.enable = true;
  _module.args.llmAgents = {
    inherit system;
    inherit (inputs) pi-agent-extensions;
    inherit aiPkgs;
    skillzPkgs = inputs.skillz.packages.${system};
    claudeCode = self.packages.${system}.claude-code;
  };
}
