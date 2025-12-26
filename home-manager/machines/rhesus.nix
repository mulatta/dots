{ config, ... }:
{
  home.username = "seungwon";
  home.homeDirectory = "/Users/seungwon";

  home.sessionVariables = {
    DOCKER_HOST = "unix://${config.home.homeDirectory}/.config/colima/default/docker.sock";
  };
}
