{
  pkgs,
  config,
  lib,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  ntfy-subscribe = self.packages.${system}.ntfy-subscribe;
in
{
  config = lib.mkMerge [
    # Long-running daemon — use launchd (macOS) or systemd (Linux)
    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.enable = true;
      launchd.agents.ntfy-subscribe = {
        enable = true;
        config = {
          ProgramArguments = [ "${ntfy-subscribe}/bin/ntfy-subscribe" ];
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
          ExecStart = "${ntfy-subscribe}/bin/ntfy-subscribe";
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
