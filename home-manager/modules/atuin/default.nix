{ pkgs, ... }:
{
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    flags = [
      "--disable-up-arrow"
    ];
    # settings = {
    #   auto_sync = true;
    #   sync_frequency = "5m";
    #   sync_address = "https://api.atuin.sh";
    #   search_mode = "prefix";
    # };
    enableZshIntegration = true;
    enableFishIntegration = true;
    daemon.enable = true;
  };
}
