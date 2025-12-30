{
  pkgs,
  lib,
  config,
  ...
}:
let
  socketPath = "${config.home.homeDirectory}/.local/share/atuin/daemon.sock";
in
{
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    flags = [ "--disable-up-arrow" ];
    enableZshIntegration = true;
    enableFishIntegration = true;
    daemon.enable = false;
    settings = {
      sync_address = "http://taps.x:58888";
    };
  };

  launchd.agents.atuin-daemon = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      Label = "com.atuin.daemon";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        "rm -f ${socketPath}; exec ${pkgs.atuin}/bin/atuin daemon"
      ];
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/atuin-daemon.stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/atuin-daemon.stderr.log";
    };
  };
}
