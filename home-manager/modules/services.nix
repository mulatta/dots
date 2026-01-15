{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Pueue task queue
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

  # Atuin sync service (instead of daemon)
  systemd.user.timers.atuin-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Atuin auto sync";
    Timer.OnUnitActiveSec = "1h";
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.atuin-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Atuin auto sync";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.atuin}/bin/atuin sync";
      IOSchedulingClass = "idle";
    };
  };

  launchd.agents.atuin-sync = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.atuin}/bin/atuin" "sync" ];
      StartInterval = 3600;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "${config.xdg.stateHome}/atuin-sync.log";
      StandardErrorPath = "${config.xdg.stateHome}/atuin-sync.err";
    };
  };
}
