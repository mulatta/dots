{
  inputs,
  self,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = inputs.llm-agents.packages.${system};
  bioPkgs = inputs.bioinformatics-toolkits.packages.${system};
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
    inherit bioPkgs;
    skillzPkgs = inputs.skillz.packages.${system};
    nixbot-cli = inputs.nixbot.packages.${system}.nixbot-cli;
    claudeCode = self.packages.${system}.claude-code;
  };
}
