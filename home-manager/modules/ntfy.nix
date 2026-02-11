{
  pkgs,
  config,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    # Long-running daemon — use launchd (macOS) or systemd (Linux)
    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.enable = true;
      launchd.agents.ntfy-subscribe = {
        enable = true;
        config = {
          ProgramArguments = [ "${pkgs.ntfy-subscribe}/bin/ntfy-subscribe" ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${config.xdg.stateHome}/ntfy-subscribe.log";
          StandardErrorPath = "${config.xdg.stateHome}/ntfy-subscribe.err";
          EnvironmentVariables = {
            HOME = config.home.homeDirectory;
          };
        };
      };
    })

    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.services.ntfy-subscribe = {
        Unit.Description = "ntfy push notification subscriber";
        Service = {
          ExecStart = "${pkgs.ntfy-subscribe}/bin/ntfy-subscribe";
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
