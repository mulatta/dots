{
  clan-cli,
  jq,
  nix,
  openssh,
  writeShellApplication,
}:

writeShellApplication {
  name = "instant-deploy";

  runtimeInputs = [
    clan-cli
    jq
    nix
    openssh
  ];

  text = ''
    usage() {
      cat <<'EOF'
    Usage: instant-deploy [OPTIONS] MACHINE

    Cache-only deploy for Clan-managed NixOS machines.

    The command evaluates the machine once, realises the final NixOS system path on
    the target with local builds disabled, uploads Clan vars once, then switches to
    that exact system path.

    Options:
      --flake PATH     Flake path/ref. Defaults to $NH_FLAKE, then $CLAN_DIR, then .
      --no-vars        Skip `clan vars upload`.
      --no-check       Set NIXOS_NO_CHECK=1 for switch-to-configuration.
      -h, --help       Show this help.

    Notes:
      This does not run Clan var generators. Run `clan vars generate MACHINE` first
      when adding new generated vars.
    EOF
    }

    flake="''${NH_FLAKE:-''${CLAN_DIR:-.}}"
    upload_vars=1
    no_check=0
    machine=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --flake)
          if [ "$#" -lt 2 ]; then
            echo "instant-deploy: --flake needs path" >&2
            exit 2
          fi
          flake=$2
          shift 2
          ;;
        --no-vars)
          upload_vars=0
          shift
          ;;
        --no-check)
          no_check=1
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        --)
          shift
          break
          ;;
        -*)
          echo "instant-deploy: unknown option: $1" >&2
          usage >&2
          exit 2
          ;;
        *)
          if [ -n "$machine" ]; then
            echo "instant-deploy: expected one MACHINE" >&2
            usage >&2
            exit 2
          fi
          machine=$1
          shift
          ;;
      esac
    done

    if [ "$#" -gt 0 ]; then
      if [ -n "$machine" ] || [ "$#" -ne 1 ]; then
        echo "instant-deploy: expected one MACHINE" >&2
        usage >&2
        exit 2
      fi
      machine=$1
    fi

    if [ -z "$machine" ]; then
      echo "instant-deploy: missing MACHINE" >&2
      usage >&2
      exit 2
    fi

    echo "instant-deploy: evaluating $machine from $flake" >&2
    machine_json=$(
      nix eval --json "$flake#nixosConfigurations.$machine" --apply '
        c: {
          targetHost = c.config.clan.core.networking.targetHost;
          toplevel = c.config.system.build.toplevel;
        }
      '
    )

    target_host=$(jq -r .targetHost <<<"$machine_json")
    toplevel=$(jq -r .toplevel <<<"$machine_json")

    if [ -z "$target_host" ] || [ "$target_host" = null ]; then
      echo "instant-deploy: $machine has no config.clan.core.networking.targetHost" >&2
      exit 1
    fi

    if [ -z "$toplevel" ] || [ "$toplevel" = null ]; then
      echo "instant-deploy: $machine has no config.system.build.toplevel" >&2
      exit 1
    fi

    echo "instant-deploy: target $target_host" >&2
    echo "instant-deploy: system $toplevel" >&2
    echo "instant-deploy: realising system on target without builders" >&2

    ssh -- "$target_host" bash -s -- "$toplevel" <<'REMOTE_PREFETCH'
    set -euo pipefail
    PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin:$PATH
    toplevel=$1
    empty_builders=
    nix-store \
      --option narinfo-cache-negative-ttl 0 \
      --option max-jobs 0 \
      --option builders "$empty_builders" \
      --option fallback false \
      -r "$toplevel"
    REMOTE_PREFETCH

    if [ "$upload_vars" -eq 1 ]; then
      echo "instant-deploy: uploading Clan vars" >&2
      clan vars upload --flake "$flake" "$machine"
    else
      echo "instant-deploy: skipping Clan vars upload" >&2
    fi

    echo "instant-deploy: switching target to exact system path" >&2
    ssh -- "$target_host" bash -s -- "$toplevel" "$no_check" <<'REMOTE_SWITCH'
    set -euo pipefail
    PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin:$PATH
    toplevel=$1
    no_check=$2

    if [ "$no_check" = 1 ]; then
      export NIXOS_NO_CHECK=1
    fi

    nix-env --profile /nix/var/nix/profiles/system --set "$toplevel"
    "$toplevel/bin/switch-to-configuration" switch
    REMOTE_SWITCH

    echo "instant-deploy: done" >&2
  '';
}
