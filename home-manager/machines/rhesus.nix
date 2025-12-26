{ config, ... }:
{
  home.username = "seungwon";
  home.homeDirectory = "/Users/seungwon";

  home.sessionVariables = {
    DOCKER_HOST = "unix://${config.home.homeDirectory}/.colima/default/docker.sock";
  };
}
