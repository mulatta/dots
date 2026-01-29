{ pkgs, ... }:
{
  imports = [
    ./gpu-support.nix
    ../modules/llm-agents.nix
  ];

  home.packages = with pkgs; [
    uv
    pixi
  ];
}
