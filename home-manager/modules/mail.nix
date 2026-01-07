{
  pkgs,
  config,
  lib,
  ...
}:
let
  maildir = "${config.home.homeDirectory}/mail";
  certFile =
    if pkgs.stdenv.isDarwin then "/etc/ssl/cert.pem" else "/etc/ssl/certs/ca-certificates.crt";

  # email-sync script wrapping mbsync, notmuch, afew
  email-sync = pkgs.writeShellApplication {
    name = "email-sync";
    runtimeInputs =
      with pkgs;
      [
        isync
        notmuch
        afew
        uutils-coreutils-noprefix
        gnugrep
        jq
        rbw
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ libnotify ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ terminal-notifier ];
    text = ''
      set -euo pipefail

      echo "Syncing emails from IMAP servers..."
      mbsync -a

      if [ ! -d "${maildir}/.notmuch" ]; then
        echo "Initializing notmuch database..."
        notmuch new
      fi

      echo "Indexing new emails..."
      notmuch new

      echo "Tagging emails with afew..."
      PYTHONWARNINGS="ignore::UserWarning" afew -tn || true

      echo "Email sync complete."
    '';
  };

  # Open message in Thunderbird (reads from stdin, saves to temp file, opens)

  # msmtp wrapper that saves sent mail to maildir
  msmtp-with-sent = pkgs.writeShellScriptBin "msmtp" ''
    tmpfile=$(mktemp)
    trap "rm -f $tmpfile" EXIT

    cat > "$tmpfile"

    if ${pkgs.msmtp}/bin/msmtp "$@" < "$tmpfile"; then
      timestamp=$(date +%s)
      hostname=$(hostname)
      pid=$$
      random=$RANDOM
      filename="''${timestamp}.''${pid}_''${random}.''${hostname}:2,S"

      # Ensure Sent directory exists
      mkdir -p "${maildir}/.Sent/cur"
      cp "$tmpfile" "${maildir}/.Sent/cur/$filename"

      ${pkgs.notmuch}/bin/notmuch new >/dev/null 2>&1 || true
      exit 0
    else
      exit $?
    fi
  '';
in
lib.mkMerge [
  {
    home.packages = with pkgs; [
      mblaze
      w3m
      email-sync
      rbw
      gnupg
    ];

    accounts.email = {
      maildirBasePath = maildir;
      accounts.mulatta = {
        primary = true;
        address = "seungwon@mulatta.io";
        userName = "seungwon@mulatta.io";
        realName = "seungwon";
        passwordCommand = "rbw get 'mulatta.io'";

        imap = {
          host = "mail.mulatta.io";
          port = 993;
          tls.enable = true;
        };

        smtp = {
          host = "mail.mulatta.io";
          port = 465;
          tls.enable = true;
        };

        mbsync = {
          enable = true;
          create = "both";
          expunge = "both";
          patterns = [
            "*"
            "!Shared Folders"
            "!Shared Folders/*"
          ];
          extraConfig.account = {
            TLSType = "IMAPS";
            CertificateFile = certFile;
          };
          extraConfig.local = {
            SubFolders = "Verbatim";
          };
        };

        aerc = {
          enable = true;
          extraAccounts = {
            source = "notmuch://${maildir}";
            outgoing = "msmtp";
            default = "INBOX";
            copy-to = "Sent";
            archive = "Archive";
            postpone = "Drafts";
            query-map = "${maildir}/query-map";
            maildir-store = "${maildir}/mulatta";
            multi-file-strategy = "act-all";
          };
        };

        msmtp = {
          enable = true;
          extraConfig = {
            tls_starttls = "off";
          };
        };

        notmuch.enable = true;
      };
    };

    programs.mbsync.enable = true;

    programs.msmtp = {
      enable = true;
      package = msmtp-with-sent; # wrapper that saves sent mail to maildir
    };

    programs.aerc = {
      enable = true;
      extraConfig = {
        general = {
          unsafe-accounts-conf = true;
          pgp-provider = "auto";
          disable-ipc = true;
          log-file = "~/.local/state/aerc.log";
        };
        ui = {
          styleset-name = "dracula";
        };
        openers = {
          "text/html" = "${pkgs.w3m}/bin/w3m -T text/html";
          "message/rfc822" =
            if pkgs.stdenv.isDarwin then
              "/usr/bin/open -a Thunderbird" # macOS system binary
            else
              "${pkgs.thunderbird}/bin/thunderbird";
          # Fallback to system handler
          "*" =
            if pkgs.stdenv.isDarwin then
              "/usr/bin/open" # macOS system binary (no nix equivalent)
            else
              "${pkgs.xdg-utils}/bin/xdg-open";
        };
      };
      stylesets.dracula = builtins.readFile "${pkgs.aerc}/share/aerc/stylesets/dracula";
    };

    # Custom aerc bindings - include defaults then add custom
    xdg.configFile."aerc/binds.conf".text = ''
      # Include system defaults
      ${builtins.readFile "${pkgs.aerc}/share/aerc/binds.conf"}

      # Custom bindings
      [messages]
      Q = :quit<Enter>
      <C-o> = :pipe -m open-in-thunderbird<Enter>

      [view]
      <C-o> = :pipe -m open-in-thunderbird<Enter>
    '';

    programs.notmuch = {
      enable = true;
      new = {
        tags = [ "new" ];
        ignore = [
          ".mbsyncstate"
          ".uidvalidity"
        ];
      };
      search.excludeTags = [
        "deleted"
        "spam"
      ];
      maildir.synchronizeFlags = true;
    };

    programs.afew = {
      enable = true;
      extraConfig = ''
        [SpamFilter]
        [KillThreadsFilter]
        [ListMailsFilter]
        [ArchiveSentMailsFilter]
        [FolderNameFilter]
        [InboxFilter]
      '';
    };
  }

  # Linux: systemd user services for email sync
  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.services.mbsync = {
      Unit.Description = "Mailbox synchronization";
      Service = {
        Type = "oneshot";
        ExecStart = "${email-sync}/bin/email-sync";
      };
    };

    systemd.user.timers.mbsync = {
      Unit.Description = "Mailbox synchronization timer";
      Timer = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  })

  # macOS: launchd agents for email sync
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.enable = true;
    launchd.agents.mbsync = {
      enable = true;
      config = {
        ProgramArguments = [ "${email-sync}/bin/email-sync" ];
        StartInterval = 300;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/.local/state/mbsync.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/state/mbsync.err";
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };
  })
]
