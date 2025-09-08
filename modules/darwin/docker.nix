{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    colima
    docker
    docker-compose
  ];
}
