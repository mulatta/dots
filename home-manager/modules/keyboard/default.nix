{ pkgs, lib, ... }:
{
  home.packages = [ pkgs.keymapp ];

  # Karabiner replaces symlinks with regular files at runtime,
  # so we copy instead of symlinking and reload after.
  home.activation.karabiner = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      karabiner_dir="$HOME/.config/karabiner"
      target="$karabiner_dir/karabiner.json"
      run mkdir -p "$karabiner_dir"

      # Only rewrite and reload when the config actually changed, so an
      # unrelated activation doesn't bounce the running Karabiner profile.
      if ! cmp -s "${./karabiner.json}" "$target"; then
        run cp -f "${./karabiner.json}" "$target"

        karabiner="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
        if [[ -x "$karabiner" ]]; then
          run "$karabiner" --select-profile "$("$karabiner" --show-current-profile-name)"
        fi
      fi
    ''
  );
}
