{ pkgs, config, ... }:
let
  colimaWrapper = pkgs.writeShellScript "colima-launchd" ''
    # Clean up any orphan limactl processes from previous ungraceful shutdowns
    pkill -9 -f '\.limactl-wrapped' 2>/dev/null || true
    pkill -9 -f 'limactl.*hostagent' 2>/dev/null || true

    # Also stop any existing colima instance gracefully
    ${pkgs.colima}/bin/colima stop 2>/dev/null || true

    cleanup() {
      ${pkgs.colima}/bin/colima stop
      exit 0
    }
    trap cleanup SIGTERM SIGINT

    ${pkgs.colima}/bin/colima start --foreground &
    wait $!
  '';

  dockerContextScript = pkgs.writeShellScript "set-docker-context" ''
    # Wait for colima context to be available (max 30s)
    for i in {1..30}; do
      if ${pkgs.docker}/bin/docker context inspect colima &> /dev/null; then
        ${pkgs.docker}/bin/docker context use colima &> /dev/null
        exit 0
      fi
      sleep 1
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
    colima
    qemu
    lima
  ];

  # Colima auto-start via launchd
  launchd.user.agents.colima = {
    serviceConfig = {
      ProgramArguments = [ "${colimaWrapper}" ];
      EnvironmentVariables = {
        PATH = "${pkgs.docker}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin";
      };
      KeepAlive = true;
      RunAtLoad = true;
      ExitTimeOut = 30;
      StandardOutPath = "/tmp/colima.stdout.log";
      StandardErrorPath = "/tmp/colima.stderr.log";
    };
  };

  # Set docker context when colima socket is created
  launchd.user.agents.docker-context = {
    serviceConfig = {
      ProgramArguments = [ "${dockerContextScript}" ];
      WatchPaths = [
        "${config.users.users.${config.system.primaryUser}.home}/.config/colima/default/docker.sock"
      ];
      RunAtLoad = true;
      StandardOutPath = "/tmp/docker-context.stdout.log";
      StandardErrorPath = "/tmp/docker-context.stderr.log";
    };
  };
}
