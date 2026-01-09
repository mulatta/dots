{ pkgs, ... }:
{
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    flags = [ "--disable-up-arrow" ];
    enableZshIntegration = true;
    enableFishIntegration = true;
    daemon.enable = true;
    settings = {
      sync_address = "https://atuin.mulatta.io";
      auto_sync = true;
    };
  };
}
