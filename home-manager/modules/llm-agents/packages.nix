{
  pkgs,
  llmAgents,
  self,
  ...
}:
let
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  inherit (llmAgents)
    aiPkgs
    claudeCode
    skillzPkgs
    nixbot-cli
    ;

  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiPkgs.qmd.override { cudaSupport = true; }
    else
      aiPkgs.qmd;
in
{
  home.sessionVariables.AI_MEMORY_SERVER_URL = "http://malt.x:49374";

  home.packages = [
    selfPkgs.archify-cli
    selfPkgs.claude-md
    selfPkgs.pim
    pkgs.pueue
  ]
  ++ [
    claudeCode # custom wrapper, flake package output
    qmd # local binding; CUDA-grafted on GPU hosts
    nixbot-cli
    skillzPkgs.biorefs-cli
    skillzPkgs.drawio-cli
    aiPkgs.ai-memory
    aiPkgs.apm
    aiPkgs.ccstatusline
    aiPkgs.codex
    aiPkgs.ctx
    aiPkgs.git-surgeon
    aiPkgs.jscpd
    aiPkgs.officecli
    aiPkgs.prime-agent
    aiPkgs.tuicr
    aiPkgs.zat
  ];
}
