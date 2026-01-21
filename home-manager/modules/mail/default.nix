# Mail module - config managed by stow (home/.config/)
# This module only provides packages, scripts, and services
{
  pkgs,
  config,
  lib,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  rbw-pinentry = self.packages.${system}.rbw-pinentry;
  claude-code = self.inputs.llm-agents.packages.${system}.claude-code;
  maildir = "${config.home.homeDirectory}/mail";
  afewConfigDir = "${config.home.homeDirectory}/.config/afew";

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
        w3m # for HTML to text conversion in ClaudeSpamFilter
        khard # for contact lookup in ClaudeSpamFilter
        claude-code # for spam classification
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [ libnotify ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ terminal-notifier ];
    text = ''
      set -euo pipefail

      # Set PYTHONPATH for afew custom filters (ClaudeSpamFilter, UserCorrectionFilter)
      export PYTHONPATH="${afewConfigDir}:''${PYTHONPATH:-}"
      export NOTMUCH_CONFIG="$HOME/.config/notmuch/default/config"

      # Prevent concurrent runs with lock directory (atomic on all platforms)
      LOCKDIR="$HOME/.local/state/email-sync.lock"
      mkdir -p "$(dirname "$LOCKDIR")"
      cleanup() { rmdir "$LOCKDIR" 2>/dev/null || true; }
      trap cleanup EXIT
      if ! mkdir "$LOCKDIR" 2>/dev/null; then
        echo "Another email-sync is running, exiting."
        exit 0
      fi

      # Try to unlock if locked (keychain will provide password automatically)
      if ! rbw unlocked 2>/dev/null; then
        echo "rbw vault is locked, attempting unlock via keychain..."
        if ! rbw unlock 2>/dev/null; then
          echo "Failed to unlock rbw vault, skipping sync."
          exit 0
        fi
      fi

      echo "Syncing emails from IMAP servers..."
      mbsync -c "$HOME/.config/isyncrc" -a

      if [ ! -d "${maildir}/.notmuch" ]; then
        echo "Initializing notmuch database..."
        notmuch new
      fi

      echo "Indexing new emails..."
      notmuch new

      echo "Tagging emails with afew (including Claude spam filter)..."
      afew -tn 2>&1 || true

      echo "Moving emails based on tags..."
      afew --move-mails --all 2>&1 || true

      # Resync after MailMover to push folder changes to server
      echo "Resyncing after folder moves..."
      mbsync -c "$HOME/.config/isyncrc" -a || true

      # Check for new mail and send notification (exclude spam)
      new_query="date:7days.. AND tag:unread AND NOT tag:notified AND NOT tag:spam"
      new_count=$(notmuch count "$new_query")
      if [ "$new_count" -gt 0 ]; then
        echo "Found $new_count new email(s) to notify"

        # Get summary of new emails (up to 3 subjects), escape special chars
        summary=$(notmuch search --format=json --limit=3 "$new_query" | jq -r '.[].subject // "No subject"' | head -3 | paste -sd ', ' -)
        summary="''${summary:-New messages}"

    ''
    + (
      if pkgs.stdenv.isDarwin then
        ''
          terminal-notifier \
            -title "New Mail ($new_count)" \
            -message "$summary" \
            -group "email-sync" \
            -sound default || true
        ''
      else
        ''
          notify-send \
            -u normal \
            -i mail-unread \
            "New Mail ($new_count)" \
            "$summary" || true
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
    ./sieve.nix
    ./thunderbird.nix
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
        pkgs.w3m # for HTML conversion in spam filter
        pkgs.khard # for contact lookup in spam filter
        claude-code # for spam classification
      ];
    }

    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.services.mbsync = {
        Unit.Description = "Mailbox synchronization";
        Service = {
          Type = "oneshot";
          ExecStart = "${email-sync}/bin/email-sync";
          Environment = [
            "PYTHONPATH=${afewConfigDir}"
            "PATH=${claude-code}/bin:${pkgs.rbw}/bin:/usr/bin:/bin"
          ];
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
          EnvironmentVariables = {
            HOME = config.home.homeDirectory;
            PATH = "${rbw-pinentry}/bin:${pkgs.rbw}/bin:${claude-code}/bin:/usr/bin:/bin";
            PYTHONPATH = afewConfigDir;
          };
        };
      };
    })
  ];
}
