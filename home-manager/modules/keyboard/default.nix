{ pkgs, lib, ... }:
{
  home.packages = [ pkgs.keymapp ];

  # Karabiner replaces symlinks with regular files at runtime,
  # so we copy instead of symlinking and reload after.
  home.activation.karabiner = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      karabiner_dir="$HOME/.config/karabiner"
      run mkdir -p "$karabiner_dir"
      run cp -f "${./karabiner.json}" "$karabiner_dir/karabiner.json"

      karabiner="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
      if [[ -x "$karabiner" ]]; then
        run "$karabiner" --select-profile "$("$karabiner" --show-current-profile-name)"
      fi
    ''
  );
}
