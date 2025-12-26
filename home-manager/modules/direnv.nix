{
  pkgs,
  lib,
  ...
}:
{
  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv = {
      enable = true;
      package = pkgs.nix-direnv;
    };
    config = {
      global = {
        load_dotenv = true;
        hide_env_diff = true;
        log_format = lib.mkForce "$(tput setaf 1)%e$(tput sgr0)";
      };
    };
  };
}
