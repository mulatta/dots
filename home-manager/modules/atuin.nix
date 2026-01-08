{
  pkgs,
  lib,
  ...
}:
{
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    flags = [ "--disable-up-arrow" ];
    enableZshIntegration = true;
    enableFishIntegration = true;
    daemon.enable = false;
    settings = {
      sync_address = "https://atuin.mulatta.io";
      auto_sync = false;
    };
  };

  launchd.agents.atuin-sync = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      Label = "com.atuin.sync";
      ProgramArguments = [
        "${pkgs.atuin}/bin/atuin"
        "sync"
      ];
      StartInterval = 3600;
      StandardOutPath = "/dev/null";
      StandardErrorPath = "/dev/null";
    };
  };

  systemd.user.services.atuin-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Atuin sync";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.atuin}/bin/atuin sync";
    };
  };

  systemd.user.timers.atuin-sync = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Atuin sync timer";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
