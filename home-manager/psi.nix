{ ... }:
{
  imports = [
    ./modules/docker.nix
    ./modules/gpu-support.nix
    ./modules/ai.nix
  ];
}
