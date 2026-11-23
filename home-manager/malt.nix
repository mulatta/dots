{
  inputs,
  pkgs,
  ...
}:
let
  aiPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ./modules/chat.nix
  ];

  # ChatGPT remote workspaces require Codex in the remote login shell.
  home.packages = [ aiPkgs.codex ];
}
