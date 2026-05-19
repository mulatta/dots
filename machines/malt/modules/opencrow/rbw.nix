{
  config,
  lib,
  pkgs,
  ...
}:
let
  rbwShim = pkgs.writeShellScriptBin "rbw" (
    ''
      set -eu

      if [ "$#" -lt 1 ] || [ "$1" != "get" ]; then
        echo "opencrow rbw shim: only 'rbw get <entry>' is supported" >&2
        exit 64
      fi

      shift
      if [ "$#" -lt 1 ]; then
        echo "opencrow rbw shim: missing entry for 'rbw get'" >&2
        exit 64
      fi

      entry=$*
      case "$entry" in
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (entry: credentialFile: ''
        ${lib.escapeShellArg entry})
          cat ${lib.escapeShellArg "/run/credentials/opencrow.service/${credentialFile}"}
          ;;
      '') config.services.opencrow.rbwEntries
    )
    + ''
        *)
          echo "opencrow rbw shim: unknown entry: $entry" >&2
          exit 66
          ;;
      esac
    ''
  );
in
{
  options.services.opencrow.rbwEntries = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Map rbw entry names to systemd credential file names for the
      opencrow service.
    '';
  };

  config.services.opencrow.extraPackages = [ rbwShim ];
}
