{
  writeShellApplication,
  notmuch,
  coreutils,
  findutils,
}:

writeShellApplication {
  name = "aerc-empty-trash";

  runtimeInputs = [
    notmuch
    coreutils
    findutils
  ];

  text = ''
    NOTMUCH_CONFIG="''${NOTMUCH_CONFIG:-$HOME/.config/notmuch/default/config}"
    export NOTMUCH_CONFIG

    count=$(notmuch count tag:trash)
    if [ "$count" -eq 0 ]; then
      echo "Trash is empty."
      exit 0
    fi

    echo "Permanently deleting $count trashed messages..."
    notmuch search --output=files tag:trash | xargs rm -f
    notmuch new --quiet
    echo "Done. $count messages permanently deleted."
  '';
}
