# Calendar module - configs managed by stow (home/.config/)
# This module only provides packages, scripts, and services
{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Python environment for calendar-notify
  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      icalendar
      python-dateutil
      pytz
    ]
  );

  # Calendar sync script using vdirsyncer
  calendar-sync = pkgs.writeShellApplication {
    name = "calendar-sync";
    runtimeInputs = with pkgs; [
      vdirsyncer
      rbw
    ];
    text = ''
      # Check if rbw is unlocked (skip if not to avoid pinentry spam)
      if ! rbw unlocked 2>/dev/null; then
        echo "rbw vault is locked, skipping sync."
        exit 0
      fi

      vdirsyncer discover || true
      vdirsyncer sync
    '';
  };

  # Calendar notification script
  calendar-notify = pkgs.writeShellApplication {
    name = "calendar-notify";
    runtimeInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.libnotify ];
    text = ''
      exec ${pythonEnv}/bin/python ${./calendar-notify.py}
    '';
  };

  dataHome = config.xdg.dataHome;
in
lib.mkMerge [
  {
    home.packages = [
      calendar-sync
      calendar-notify
      pkgs.khal
      pkgs.khard
      pkgs.vdirsyncer
      pkgs.todoman
    ];

    # Create calendar/contacts directories
    home.activation.createPimDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${dataHome}/calendars"
      run mkdir -p "${dataHome}/contacts"
      run mkdir -p "${dataHome}/vdirsyncer/status"
    '';
  }

  # Linux: systemd user services
  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.services.calendar-sync = {
      Unit = {
        Description = "Sync calendars with vdirsyncer";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${calendar-sync}/bin/calendar-sync";
      };
    };

    systemd.user.services.calendar-notify = {
      Unit = {
        Description = "Check calendar and send notifications";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${calendar-notify}/bin/calendar-notify";
        Environment = "DISPLAY=:0";
      };
    };

    systemd.user.timers.calendar-sync = {
      Unit.Description = "Sync calendars regularly";
      Timer = {
        OnCalendar = "*:0/15";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.timers.calendar-notify = {
      Unit.Description = "Check calendar for upcoming events";
      Timer = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  })

  # macOS: launchd agents
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.enable = true;
    launchd.agents.calendar-sync = {
      enable = true;
      config = {
        ProgramArguments = [ "${calendar-sync}/bin/calendar-sync" ];
        StartInterval = 900;
        RunAtLoad = true;
        StandardOutPath = "${config.xdg.stateHome}/calendar-sync.log";
        StandardErrorPath = "${config.xdg.stateHome}/calendar-sync.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };

    launchd.agents.calendar-notify = {
      enable = true;
      config = {
        ProgramArguments = [ "${calendar-notify}/bin/calendar-notify" ];
        StartInterval = 300;
        RunAtLoad = true;
        StandardOutPath = "${config.xdg.stateHome}/calendar-notify.log";
        StandardErrorPath = "${config.xdg.stateHome}/calendar-notify.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };
  })
]
