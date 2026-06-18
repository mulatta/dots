# Calendar module - configs managed by stow (home/.config/)
# This module only provides packages, scripts, and services.
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

  calendarNotifyScript = pkgs.writeShellScriptBin "calendar-notify" ''
    #!/usr/bin/env bash
    ${lib.optionalString pkgs.stdenv.isLinux ''export PATH="${pkgs.libnotify}/bin:$PATH"''}
    exec ${pythonEnv}/bin/python ${./calendar-notify.py}
  '';

  calendarSyncScript = pkgs.writeShellScriptBin "calendar-sync" ''
    #!/usr/bin/env bash
    # Sync calendars with vdirsyncer
    export PATH="${pkgs.rbw}/bin:$PATH"
    ${pkgs.vdirsyncer}/bin/vdirsyncer sync
  '';

  vdirsyncerPostHook = pkgs.writeShellScriptBin "vdirsyncer-post-hook" ''
    # vdirsyncer post_hook: commit after item creation/modification
    # Called with the path of the new/updated file as $1
    set -euo pipefail

    file="$1"
    dir="$(${pkgs.coreutils}/bin/dirname "$file")"

    cd "$dir"
    if ! ${pkgs.git}/bin/git rev-parse --show-toplevel &>/dev/null; then
        # File is in a collection subdir (e.g. calendars/Personal/foo.ics),
        # init the repo one level up at the storage root.
        ${pkgs.git}/bin/git init --quiet ..
        ${pkgs.git}/bin/git -C .. add -A
        ${pkgs.git}/bin/git -C .. commit -m "Initial commit" --quiet || true
    fi

    ${pkgs.git}/bin/git add "$file"
    ${pkgs.git}/bin/git commit -m "Update $(${pkgs.coreutils}/bin/basename "$file")" --quiet || true
  '';

  vdirsyncerPreDeletionHook = pkgs.writeShellScriptBin "vdirsyncer-pre-deletion-hook" ''
    # vdirsyncer pre_deletion_hook: commit deletion of items
    # Called with the path of the file to be deleted as $1
    set -euo pipefail

    file="$1"
    dir="$(${pkgs.coreutils}/bin/dirname "$file")"

    cd "$dir"
    if ! ${pkgs.git}/bin/git rev-parse --show-toplevel &>/dev/null; then
        # File is in a collection subdir (e.g. calendars/Personal/foo.ics),
        # init the repo one level up at the storage root.
        ${pkgs.git}/bin/git init --quiet ..
        ${pkgs.git}/bin/git -C .. add -A
        ${pkgs.git}/bin/git -C .. commit -m "Initial commit" --quiet || true
    fi

    ${pkgs.git}/bin/git rm --quiet "$file"
    ${pkgs.git}/bin/git commit -m "Delete $(${pkgs.coreutils}/bin/basename "$file")" --quiet || true
  '';

  dataHome = config.xdg.dataHome;
in
lib.mkMerge [
  {
    home.packages = with pkgs; [
      khal
      khard
      vdirsyncer
      todoman
      calendarNotifyScript
      calendarSyncScript
      vdirsyncerPostHook
      vdirsyncerPreDeletionHook
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
        ExecStart = "${calendarSyncScript}/bin/calendar-sync";
      };
    };

    systemd.user.services.calendar-notify = {
      Unit = {
        Description = "Check calendar and send notifications";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${calendarNotifyScript}/bin/calendar-notify";
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
        ProgramArguments = [ "${calendarSyncScript}/bin/calendar-sync" ];
        StartCalendarInterval = [
          { Minute = 0; }
          { Minute = 15; }
          { Minute = 30; }
          { Minute = 45; }
        ];
        RunAtLoad = true;
        StandardOutPath = "${config.xdg.stateHome}/calendar-sync.log";
        StandardErrorPath = "${config.xdg.stateHome}/calendar-sync.err";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          PATH = "${pkgs.rbw-pinentry}/bin:${pkgs.rbw}/bin:/usr/bin:/bin";
        };
      };
    };

    launchd.agents.calendar-notify = {
      enable = true;
      config = {
        ProgramArguments = [ "${calendarNotifyScript}/bin/calendar-notify" ];
        StartCalendarInterval = [
          { Minute = 0; }
          { Minute = 5; }
          { Minute = 10; }
          { Minute = 15; }
          { Minute = 20; }
          { Minute = 25; }
          { Minute = 30; }
          { Minute = 35; }
          { Minute = 40; }
          { Minute = 45; }
          { Minute = 50; }
          { Minute = 55; }
        ];
        RunAtLoad = true;
        StandardOutPath = "${config.xdg.stateHome}/calendar-notify.log";
        StandardErrorPath = "${config.xdg.stateHome}/calendar-notify.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };
  })
]
