{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    pueue
  ];

  launchd.agents.pueued = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.pueue}/bin/pueued"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/pueued.log";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/pueued.log";
    };
  };

  home.file."Library/Application Support/pueue/pueue.yml".text = ''
    shared:
      pueue_directory: "~/.local/share/pueue"

    daemon:
      defult_parallel_tasks: 4

    client:
      read_local_logs: true

    profiles:
      psi:
        shared:
          pueue_directory: "~/.local/share/pueue_psi"
          use_unix_socket: false
          host: "127.0.0.1"
          port: "6924"

        client:
          read_local_logs: false
  '';
}
