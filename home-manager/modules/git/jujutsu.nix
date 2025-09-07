{ config, ... }:
{
  programs.jujutsu = {
    enable = true;
    settings = {
      user.email = config.programs.git.userEmail;
      user.name = config.programs.git.userName;
    };
  };
}
