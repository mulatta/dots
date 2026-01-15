# Mail module - config managed by stow (home/.config/)
# This module only provides packages, scripts, and services
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
    text =
      ''
        set -euo pipefail

        echo "Syncing emails from IMAP servers..."
        mbsync -c "$HOME/.config/isyncrc" -a

        if [ ! -d "${maildir}/.notmuch" ]; then
          echo "Initializing notmuch database..."
          notmuch new
        fi

        echo "Indexing new emails..."
        notmuch new

        echo "Tagging emails with afew..."
        NOTMUCH_CONFIG="$HOME/.config/notmuch/default/config" PYTHONWARNINGS="ignore::UserWarning" afew -tn || true

        # Check for new mail and send notification (Mic92 style with notified tag)
        new_query="date:7days.. AND tag:unread AND NOT tag:notified"
        new_count=$(notmuch count "$new_query")
        if [ "$new_count" -gt 0 ]; then
          echo "Found $new_count new email(s) to notify"

          # Get summary of new emails (up to 3 subjects)
          summary=$(notmuch search --format=json --limit=3 "$new_query" | jq -r '.[].subject' | tr '\n' ' ')

      ''
      + (
        if pkgs.stdenv.isDarwin then
          ''
            terminal-notifier \
              -title "New Mail ($new_count)" \
              -message "$summary" \
              -group "email-sync" \
              -sound default
          ''
        else
          ''
            notify-send \
              -u normal \
              -i mail-unread \
              "New Mail ($new_count)" \
              "$summary"
          ''
      )
      + ''
          # Mark as notified to prevent duplicate notifications
          notmuch tag +notified -- "$new_query"
        fi

        echo "Email sync complete."
      '';
  };

  msmtp-wrapper = pkgs.writeShellScriptBin "msmtp" ''
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
  ];

  config = lib.mkMerge [
    {
      home.packages = [
        email-sync
        msmtp-wrapper
        pkgs.isync
        pkgs.notmuch
        pkgs.afew
        pkgs.rbw
        pkgs.gnupg
      ];
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
