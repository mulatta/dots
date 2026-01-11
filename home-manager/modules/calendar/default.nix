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
in
lib.mkMerge [
  {
    home.packages = [
      calendar-sync
      calendar-notify
      pkgs.rbw
      pkgs.khal
      pkgs.khard
    ];

    # Base paths for calendar and contacts
    accounts.calendar.basePath = "${config.xdg.dataHome}/calendars";
    accounts.contact.basePath = "${config.xdg.dataHome}/contacts";

    # Calendar account (CalDAV via Nextcloud)
    accounts.calendar.accounts.nextcloud = {
      primary = true;
      primaryCollection = "personal";
      local = {
        type = "filesystem";
        fileExt = ".ics";
      };
      remote = {
        type = "caldav";
        url = "https://cloud.mulatta.io/remote.php/dav/calendars/seungwon%40idm.mulatta.io/";
        userName = "seungwon@idm.mulatta.io";
        passwordCommand = [
          "rbw"
          "get"
          "nextcloud"
        ];
      };
      vdirsyncer = {
        enable = true;
        collections = [
          "from a"
          "from b"
        ];
        metadata = [
          "color"
          "displayname"
        ];
        conflictResolution = "remote wins";
      };
      khal = {
        enable = true;
        type = "discover";
      };
    };

    # Contact account (CardDAV via Nextcloud)
    accounts.contact.accounts.nextcloud = {
      local = {
        type = "filesystem";
        fileExt = ".vcf";
      };
      remote = {
        type = "carddav";
        url = "https://cloud.mulatta.io/remote.php/dav/addressbooks/users/seungwon%40idm.mulatta.io/";
        userName = "seungwon@idm.mulatta.io";
        passwordCommand = [
          "rbw"
          "get"
          "nextcloud"
        ];
      };
      vdirsyncer = {
        enable = true;
        collections = [
          "from a"
          "from b"
        ];
        conflictResolution = "remote wins";
      };
      khard = {
        enable = true;
        type = "discover";
        glob = "*";
      };
    };

    # Enable vdirsyncer
    programs.vdirsyncer.enable = true;

    # khal configuration
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
          highlight_event_days = true;
        };
      };
    };

    # khard configuration
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

    # todoman configuration
    programs.todoman = {
      enable = true;
      glob = "*/*";
      extraConfig = ''
        date_format = "%Y-%m-%d"
        time_format = "%H:%M"
        default_list = "personal"
        default_due = 0
      '';
    };

    # Create calendar/contacts directories
    home.activation.createPimDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${config.accounts.calendar.basePath}"
      run mkdir -p "${config.accounts.contact.basePath}"
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
