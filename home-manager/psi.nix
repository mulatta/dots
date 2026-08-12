{ ... }:
{
  imports = [
    ./modules/docker.nix
    ./modules/gpu-support.nix
    ./modules/llm-agents
  ];
}
