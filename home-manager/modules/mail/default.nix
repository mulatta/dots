{
  pkgs,
  config,
  lib,
  ...
}:
let
  maildir = "${config.home.homeDirectory}/mail";
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

      mkdir -p "${maildir}/.Sent/cur"
      cp "$tmpfile" "${maildir}/.Sent/cur/$filename"

      ${pkgs.notmuch}/bin/notmuch new >/dev/null 2>&1 || true
      exit 0
    else
      exit $?
    fi
  '';
in
{
  imports = [
    ./aerc.nix
    ./accounts.nix
  ];

  config = lib.mkMerge [
    {
      home.packages = [
        email-sync
        pkgs.rbw
        pkgs.gnupg
      ];

      programs.mbsync.enable = true;

      programs.msmtp = {
        enable = true;
        package = msmtp-with-sent;
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
    }

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

    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.enable = true;
      launchd.agents.mbsync = {
        enable = true;
        config = {
          ProgramArguments = [ "${email-sync}/bin/email-sync" ];
          StartInterval = 300;
          RunAtLoad = true;
          StandardOutPath = "${config.xdg.stateHome}/mbsync.log";
          StandardErrorPath = "${config.xdg.stateHome}/mbsync.err";
          EnvironmentVariables.HOME = config.home.homeDirectory;
        };
      };
    })
  ];
}
