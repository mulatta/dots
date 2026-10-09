{
  config,
  lib,
  pkgs,
  ...
}:
let
  applications = pkgs.buildEnv {
    name = "home-manager-applications";
    paths = config.home.packages;
    pathsToLink = [ "/Applications" ];
  };
in
{
  options.targets.darwin.managedApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Application bundles owned by Home Manager activations.";
  };

  # Keep the directory real while preserving each immutable application as a symlink.
  config.targets.darwin.linkApps.enable = false;

  config.home.activation.linkHomePackageApps =
    lib.hm.dag.entryAfter
      [
        "installPackages"
        "linkGeneration"
      ]
      ''
        target="$HOME/Applications/Home Manager Apps"

        # Migrate the directory symlink created by targets.darwin.linkApps.
        if [[ -L "$target" ]]; then
          run rm -- "$target"
        elif [[ -e "$target" && ! -d "$target" ]]; then
          echo "Cannot install Home Manager apps: $target is not a directory" >&2
          exit 1
        fi

        run mkdir -p -- "$target"
        run ${lib.getExe pkgs.rsync} \
          --recursive \
          --links \
          --delete \
          "${applications}/Applications/" \
          "$target/"
      '';

  config.home.activation.reconcileManagedDarwinApps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state_dir="${config.xdg.stateHome}/home-manager"
    manifest="$state_dir/managed-darwin-apps"
    current=$(mktemp)

    for app in ${lib.escapeShellArgs config.targets.darwin.managedApps}; do
      printf '%s\n' "$app" >> "$current"
    done

    if [[ -f "$manifest" ]]; then
      lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
      while IFS= read -r app; do
        if grep -Fqx -- "$app" "$current"; then
          continue
        fi
        case "$app" in
          "$HOME/Applications/"*) ;;
          *)
            echo "Refusing to remove managed app outside ~/Applications: $app" >&2
            exit 1
            ;;
        esac
        if [[ -e "$app" || -L "$app" ]]; then
          run "$lsregister" -u "$app" || true
          if [[ ! -L "$app" ]]; then
            run chmod -R u+w "$app" || true
          fi
          run rm -rf -- "$app"
        fi
      done < "$manifest"
    fi

    run mkdir -p -- "$state_dir"
    run install -m 600 "$current" "$manifest"
    rm -f "$current"
  '';
}
