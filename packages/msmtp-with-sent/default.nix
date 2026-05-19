{
  writeShellScriptBin,
  msmtp,
  notmuch,
}:

# Wrapper for msmtp that saves sent mail to the local maildir.
writeShellScriptBin "msmtp" ''
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  cat > "$tmpfile"

  if ${msmtp}/bin/msmtp "$@" < "$tmpfile"; then
      timestamp=$(date +%s)
      hostname=$(hostname)
      pid=$$
      random=$RANDOM
      filename="''${timestamp}.''${pid}_''${random}.''${hostname}:2,S"

      mail_root="''${MAILDIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/mail}"
      sent_dir="$mail_root/mulatta/Sent Items"
      mkdir -p "$sent_dir/cur" "$sent_dir/new" "$sent_dir/tmp"
      cp "$tmpfile" "$sent_dir/cur/$filename"

      ${notmuch}/bin/notmuch new >/dev/null 2>&1 || true

      exit 0
  else
      exit $?
  fi
''
