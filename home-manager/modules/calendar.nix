{
  pkgs,
  config,
  lib,
  ...
}:
let
  calendarsPath = "${config.home.homeDirectory}/.local/share/calendars";
  contactsPath = "${config.home.homeDirectory}/.local/share/contacts";

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
      vdirsyncer discover || true
      vdirsyncer sync
    '';
  };

  # Calendar notification script
  calendar-notify = pkgs.writeShellApplication {
    name = "calendar-notify";
    runtimeInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.libnotify ];
    text = ''
      exec ${pythonEnv}/bin/python ${./calendar/calendar-notify.py}
    '';
  };
in
lib.mkMerge [
  {
    home.packages = [
      calendar-sync
      calendar-notify
      pkgs.rbw
    ];

    programs.vdirsyncer = {
      enable = true;
      config = {
        general = {
          status_path = "~/.local/share/vdirsyncer/status/";
        };

        # Calendars
        "pair calendars" = {
          a = "calendars_local";
          b = "calendars_stalwart";
          collections = [
            "from a"
            "from b"
          ];
          metadata = [
            "color"
            "displayname"
          ];
          conflict_resolution = [
            "command"
            "vimdiff"
          ];
        };

        "storage calendars_local" = {
          type = "filesystem";
          path = calendarsPath;
          fileext = ".ics";
        };

        "storage calendars_stalwart" = {
          type = "caldav";
          url = "https://mail.mulatta.io/dav/cal/seungwon/";
          username = "seungwon@mulatta.io";
          "password.fetch" = [
            "command"
            "rbw"
            "get"
            "mulatta.io"
          ];
        };

        # Contacts
        "pair contacts" = {
          a = "contacts_local";
          b = "contacts_stalwart";
          collections = [
            "from a"
            "from b"
          ];
          conflict_resolution = [
            "command"
            "vimdiff"
          ];
        };

        "storage contacts_local" = {
          type = "filesystem";
          path = contactsPath;
          fileext = ".vcf";
        };

        "storage contacts_stalwart" = {
          type = "carddav";
          url = "https://mail.mulatta.io/dav/card/seungwon/";
          username = "seungwon@mulatta.io";
          "password.fetch" = [
            "command"
            "rbw"
            "get"
            "mulatta.io"
          ];
        };
      };
    };

    programs.khal = {
      enable = true;
      locale = {
        timeformat = "%H:%M";
        dateformat = "%Y-%m-%d";
        longdateformat = "%Y-%m-%d %a";
        datetimeformat = "%Y-%m-%d %H:%M";
        longdatetimeformat = "%Y-%m-%d %H:%M %a";
        firstweekday = 0;
      };
      settings = {
        default = {
          default_calendar = "default";
          highlight_event_days = true;
        };
      };
    };

    programs.khard = {
      enable = true;
      settings = {
        general = {
          default_action = "list";
          editor = [ "hx" ];
          merge_editor = [ "vimdiff" ];
        };
        "contact table" = {
          display = "formatted_name";
          group_by_addressbook = false;
          reverse = false;
          show_nicknames = true;
          show_uids = false;
          sort = "last_name";
          localize_dates = true;
        };
        vcard = {
          preferred_version = "3.0";
          search_in_source_files = false;
          skip_unparsable = false;
        };
      };
    };

    programs.todoman = {
      enable = true;
      settings = {
        main = {
          path = "${calendarsPath}/*";
          date_format = "%Y-%m-%d";
          time_format = "%H:%M";
          default_list = "default";
          default_due = 0;
        };
      };
    };

    # Create calendar/contacts directories
    home.activation.createPimDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${calendarsPath}/default"
      run mkdir -p "${contactsPath}/default"
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
        StandardOutPath = "${config.home.homeDirectory}/.local/state/calendar-sync.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/state/calendar-sync.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };

    launchd.agents.calendar-notify = {
      enable = true;
      config = {
        ProgramArguments = [ "${calendar-notify}/bin/calendar-notify" ];
        StartInterval = 300;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/.local/state/calendar-notify.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/state/calendar-notify.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };
  })
]
