{ pkgs, ... }:
{
  imports = [
    ../modules/llm-agents.nix
  ];

  home.packages = with pkgs; [
    seqkit
    fastqc
    viennarna
    blast
    nextflow
    uv
    pixi
  ];
}
