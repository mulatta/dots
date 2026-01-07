{
  pkgs,
  config,
  lib,
  ...
}:
let
  maildir = "${config.home.homeDirectory}/mail";
  # macOS: /etc/ssl/cert.pem, Linux: /etc/ssl/certs/ca-certificates.crt
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
        coreutils
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
      afew -tn || true

      echo "Email sync complete."
    '';
  };

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
      aerc
      mblaze
      w3m
      email-sync
      msmtp-with-sent
      rbw
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
            SSLType = "IMAPS";
          };
          extraConfig.local = {
            SubFolders = "Maildir++";
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

    programs.mbsync = {
      enable = true;
      extraConfig = ''
        CertificateFile ${certFile}
      '';
    };

    programs.msmtp = {
      enable = true;
      extraConfig = ''
        defaults
        auth on
        tls on
        tls_trust_file ${certFile}
        logfile ~/.local/state/msmtp.log
      '';
    };

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

    xdg.configFile."aerc/accounts.conf".text = ''
      [mulatta.io]
      source = notmuch://${maildir}
      outgoing = msmtp
      default = INBOX
      from = seungwon <seungwon@mulatta.io>
      copy-to = Sent
      archive = Archive
      postpone = Drafts
    '';
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
