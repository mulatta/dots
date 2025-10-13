{config, ...}: {
  imports = [
    ./modules/common.nix
  ];
  home.sessionVariables = {
    DOCKER_HOST = "unix://${config.home.homeDirectory}/.colima/default/docker.sock";
  };
  home.stateVersion = "25.05";
}
