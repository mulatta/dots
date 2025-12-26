{ pkgs, config, ... }:
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
    daemon.enable = false; # We manage it ourselves
  };

  # Custom launchd agent with socket cleanup
  launchd.agents.atuin-daemon = {
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
