{
  lib,
  stdenv,
  writeShellApplication,
  coreutils,
  ntfy-sh,
  rbw,
  terminal-notifier,
}:
writeShellApplication {
  name = "ntfy-subscribe";

  runtimeInputs = [
    coreutils
    ntfy-sh
    rbw
  ]
  ++ lib.optionals stdenv.isDarwin [ terminal-notifier ];

  text = ''
    STATE_DIR="$HOME/.local/state/ntfy"
    mkdir -p "$STATE_DIR"

    # Unlock rbw if needed
    if ! rbw unlocked 2>/dev/null; then
      if ! rbw unlock 2>/dev/null; then
        echo "Failed to unlock rbw vault, exiting."
        exit 1
      fi
    fi

    PASSWORD=$(rbw get ntfy-password)

    # Subscribe to all configured topics
    # Each message increments the unread counter and sends a native notification
    exec ntfy subscribe \
      -u "seungwon:$PASSWORD" \
      --from-config
  '';
}
