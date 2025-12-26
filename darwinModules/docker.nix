{ pkgs, ... }:
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
      ProgramArguments = [
        "${pkgs.colima}/bin/colima"
        "start"
        "--foreground"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.docker}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin";
      };
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/colima.stdout.log";
      StandardErrorPath = "/tmp/colima.stderr.log";
    };
  };
}
