{
  pkgs,
  llmAgents,
  ...
}:
let
  inherit (llmAgents)
    aiPkgs
    claudeCode
    skillzPkgs
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
  home.packages =
    (with pkgs; [
      archify-cli # dots overlay
      claude-md # dots overlay
      pim # dots overlay
      pueue
    ])
    ++ [
      claudeCode # custom wrapper, flake package output
      qmd # local binding; CUDA-grafted on GPU hosts
      skillzPkgs.biorefs-cli
      skillzPkgs.drawio-cli
      aiPkgs.apm
      aiPkgs.ccstatusline
      aiPkgs.codex
      aiPkgs.ctx
      aiPkgs.gemini-cli
      aiPkgs.git-surgeon
      aiPkgs.jscpd
      aiPkgs.officecli
      aiPkgs.tuicr
      aiPkgs.workmux
      aiPkgs.zat
    ];
}
