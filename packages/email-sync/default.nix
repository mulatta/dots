{
  lib,
  stdenv,
  writeShellApplication,
  isync,
  notmuch,
  afew,
  coreutils,
  gnugrep,
  jq,
  rbw,
  w3m,
  khard,
  claude-code,
  libnotify,
  terminal-notifier,
}:

writeShellApplication {
  name = "email-sync";

  runtimeInputs = [
    isync
    notmuch
    afew
    coreutils
    gnugrep
    jq
    rbw
    w3m
    khard
    claude-code
  ]
  ++ lib.optionals stdenv.isLinux [ libnotify ]
  ++ lib.optionals stdenv.isDarwin [ terminal-notifier ];

  text = ''
    MAILDIR="''${MAILDIR:-$HOME/mail}"
    NOTMUCH_CONFIG="''${NOTMUCH_CONFIG:-$HOME/.config/notmuch/default/config}"
    ISYNC_CONFIG="''${ISYNC_CONFIG:-$HOME/.config/isyncrc}"

    export NOTMUCH_CONFIG

    # Prevent concurrent runs with lock directory (atomic on all platforms)
    LOCKDIR="$HOME/.local/state/email-sync.lock"
    mkdir -p "$(dirname "$LOCKDIR")"
    cleanup() { rmdir "$LOCKDIR" 2>/dev/null || true; }
    trap cleanup EXIT
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
      echo "Another email-sync is running, exiting."
      exit 0
    fi

    # Try to unlock rbw if locked (keychain will provide password automatically)
    if ! rbw unlocked 2>/dev/null; then
      echo "rbw vault is locked, attempting unlock via keychain..."
      if ! rbw unlock 2>/dev/null; then
        echo "Failed to unlock rbw vault, skipping sync."
        exit 0
      fi
    fi

    echo "Syncing emails from IMAP servers..."
    mbsync -c "$ISYNC_CONFIG" -a

    # Initialize notmuch if needed
    if [ ! -d "$MAILDIR/.notmuch" ]; then
      echo "Initializing notmuch database..."
      notmuch new
    fi

    echo "Indexing new emails..."
    notmuch new

    echo "Tagging emails with afew (including Claude spam filter)..."
    PYTHONPATH="$HOME/.config/afew:$PYTHONPATH" PYTHONWARNINGS="ignore::UserWarning" \
      python3 -c "import sys; sys.argv = ['afew', '-tn']; import afew_filters; from afew.commands import main; main()" || true

    # Apply retention policies (cleanup old notifications)
    echo "Applying retention policies..."
    XDG_CONFIG_HOME="$HOME/.config/afew-cleanup" \
    PYTHONPATH="$HOME/.config/afew:$PYTHONPATH" PYTHONWARNINGS="ignore::UserWarning" \
      python3 -c "import sys; sys.argv = ['afew', '--tag', '--all']; import afew_filters; from afew.commands import main; main()" || true

    # Move emails to appropriate folders based on MailMover rules
    echo "Moving emails based on tags..."
    PYTHONPATH="$HOME/.config/afew:$PYTHONPATH" PYTHONWARNINGS="ignore::UserWarning" \
      python3 -c "import sys; sys.argv = ['afew', '--move-mails', '--all']; import afew_filters; from afew.commands import main; main()" || true

    # Delete old trash (older than 3 months)
    old_trash=$(notmuch search --output=files 'tag:trash AND date:..3months')
    if [ -n "$old_trash" ]; then
      old_count=$(echo "$old_trash" | wc -l | tr -d ' ')
      echo "Permanently deleting $old_count old trashed emails..."
      echo "$old_trash" | xargs rm -f
      notmuch new --quiet
    fi

    # Resync after moving emails
    echo "Resyncing after moves..."
    mbsync -c "$ISYNC_CONFIG" -a || true

    # Check for new mail and send notification
    new_query="date:7days.. AND tag:unread AND NOT tag:notified AND NOT tag:spam"
    new_count=$(notmuch count "$new_query")
    if [ "$new_count" -gt 0 ]; then
      echo "Found $new_count new email(s) to notify"

      # Get summary of new emails (up to 3 subjects)
      summary=$(notmuch search --format=json --limit=3 "$new_query" | jq -r '.[].subject // "No subject"' | head -3 | paste -sd ', ' -)
      summary="''${summary:-New messages}"
      # Prevent dash-starting subjects from being interpreted as CLI options
      [[ "$summary" == -* ]] && summary=" $summary"
  ''
  + (
    if stdenv.isDarwin then
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
}
