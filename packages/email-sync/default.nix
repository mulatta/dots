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
  ]
  ++ lib.optionals stdenv.isLinux [ libnotify ]
  ++ lib.optionals stdenv.isDarwin [ terminal-notifier ];

  text = ''
    NOTMUCH_CONFIG="''${NOTMUCH_CONFIG:-$HOME/.config/notmuch/default/config}"
    ISYNC_CONFIG="''${ISYNC_CONFIG:-$HOME/.config/isyncrc}"

    export NOTMUCH_CONFIG

    if [ -z "''${MAILDIR:-}" ]; then
      MAILDIR=$(notmuch config get database.path 2>/dev/null || true)
      MAILDIR="''${MAILDIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/mail}"
    fi

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

    echo "Tagging emails with afew..."
    afew -tn 2>&1 || true

    # Apply retention policies (cleanup old notifications)
    echo "Applying retention policies..."
    XDG_CONFIG_HOME="$HOME/.config/afew-cleanup" afew --tag --all 2>&1 || true

    # Delete old trash (older than 3 months)
    old_count=$(notmuch count 'tag:trash AND date:..3months')
    if [ "$old_count" -gt 0 ]; then
      echo "Permanently deleting $old_count old trashed emails..."
      notmuch search --format=text0 --output=files 'tag:trash AND date:..3months' | xargs -0 rm -f --
      notmuch new --quiet
    fi

    # Resync after local changes
    echo "Resyncing after local changes..."
    mbsync -c "$ISYNC_CONFIG" -a || true

    # Check for new mail and send notification
    new_query='date:7days.. AND tag:unread AND NOT tag:notified AND NOT tag:trash AND NOT folder:"mulatta/Junk Mail"'
    new_count=$(notmuch count "$new_query")
    if [ "$new_count" -gt 0 ]; then
      echo "Found $new_count new email(s) to notify"

      # Get summary of new emails (up to 3 subjects)
      summary=$(notmuch search --format=json --limit=3 "$new_query" | jq -r '.[].subject // "No subject"' | head -3 | paste -sd ', ' -)
      summary="''${summary:-New messages}"
  ''
  + (
    if stdenv.isDarwin then
      ''
        # Pipe message via stdin to avoid terminal-notifier argument parsing issues
        # (subjects starting with [ or - break -message flag)
        echo "$summary" | terminal-notifier \
          -title "New Mail ($new_count)" \
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
