{
  config,
  ...
}:
{
  # Atuin daemon
  services.pueue = {
    enable = true;
    settings = {
      daemon.default_parallel_tasks = 4;
      shared = {
        host = "127.0.0.1";
        port = 6924;
      };
    };
  };

  # NH clean (nix garbage collection)
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/dots";
    clean = {
      enable = true;
      dates = "monthly";
      extraArgs = "--keep 5 --keep-since 1m";
    };
  };

  # Session variables
  home.sessionVariables = {
    NIKS3_SERVER_URL = "https://niks3.mulatta.io";
  };
}
