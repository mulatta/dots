{ pkgs, ... }:
{
  imports = [
    ../modules/llm-agents.nix
  ];

  home.packages = with pkgs; [
    uv
    pixi
  ];
}
