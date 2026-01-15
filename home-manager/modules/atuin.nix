{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkMerge [
  {
    home.packages = [pkgs.atuin];
  }

  # Linux: systemd user timer + service
  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.timers.atuin-sync = {
      Unit.Description = "Atuin auto sync";
      Timer = {
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    systemd.user.services.atuin-sync = {
      Unit.Description = "Atuin auto sync";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.atuin}/bin/atuin sync";
        IOSchedulingClass = "idle";
      };
    };
  })

  # macOS: launchd agent
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents.atuin-sync = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.atuin}/bin/atuin"
          "sync"
        ];
        StartInterval = 3600;
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${config.xdg.stateHome}/atuin-sync.log";
        StandardErrorPath = "${config.xdg.stateHome}/atuin-sync.err";
      };
    };
  })
]
