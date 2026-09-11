{
  config,
  lib,
  pkgs,
  ...
}:
let
  publications = {
    blog = {
      package = "blog";
      requiredFile = "index.html";
    };
    cv = {
      package = "cv";
      requiredFile = "cv.pdf";
    };
    homepage = {
      package = "homepage";
      requiredFile = "index.html";
    };
  };

  repositoryRoot = config.services.gitea.repositoryRoot;
  publicationRoot = "/var/lib/gitea-publications";
  inherit (config.services.gitea) group user;

  mkDeployHook =
    name:
    {
      package,
      requiredFile,
    }:
    pkgs.writeShellApplication {
      name = "deploy-${name}";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gitMinimal
        pkgs.nix
        pkgs.util-linux
      ];
      text = ''
        revision="''${1:-}"
        if [[ -z "$revision" ]]; then
          while read -r _old new ref; do
            if [[ "$ref" == refs/heads/main ]] && [[ "$new" != 0000000000000000000000000000000000000000 ]]; then
              revision="$new"
            fi
          done
        fi
        [[ -n "$revision" ]] || exit 0
        if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
          echo "Gitea returned an invalid revision" >&2
          exit 1
        fi

        state=${publicationRoot}/${name}
        exec 9>"$state/deploy.lock"
        flock --exclusive 9

        repository=${repositoryRoot}/mulatta/${name}.git
        flake="git+file://$repository?rev=$revision"
        output=$(nix \
          --option accept-flake-config false \
          build \
          --no-link \
          --print-out-paths \
          "$flake#packages.x86_64-linux.${package}")

        if [[ ! -d "$output" ]] || [[ ! -f "$output/${requiredFile}" ]]; then
          echo "${name} output is not ready for publication" >&2
          exit 1
        fi

        invalid=$(find "$output" -mindepth 1 ! \( -type d -o -type f \) -print -quit)
        if [[ -n "$invalid" ]]; then
          echo "${name} output contains unsupported file: $invalid" >&2
          exit 1
        fi

        release="$state/releases/$revision"
        if [[ ! -d "$release" ]]; then
          temporary=$(mktemp --directory "$state/releases/.$revision.XXXXXX")
          trap 'rm -rf "$temporary"' EXIT
          cp --archive --no-preserve=ownership "$output"/. "$temporary"/
          chmod --recursive u=rwX,go=rX "$temporary"
          mv "$temporary" "$release"
          trap - EXIT
        fi
        touch "$release"

        next="$state/.current.$BASHPID"
        ln --force --no-dereference --symbolic "releases/$revision" "$next"
        mv --force --no-target-directory "$next" "$state/current"

        find "$state/releases" \
          -mindepth 1 \
          -maxdepth 1 \
          -type d \
          -printf '%T@ %p\n' \
          | sort --numeric-sort --reverse \
          | tail --lines=+4 \
          | cut --delimiter=' ' --fields=2- \
          | xargs --no-run-if-empty rm --force --recursive --

        echo "Published ${name} at $revision"
      '';
    };

  hooks = lib.mapAttrs mkDeployHook publications;

  installHooks = pkgs.writeShellApplication {
    name = "install-gitea-publication-hooks";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gitMinimal
    ];
    text = ''
      status=0
    ''
    + lib.concatMapAttrsStringSep "\n" (name: hook: ''
      repository=${repositoryRoot}/mulatta/${name}.git
      if [[ -d "$repository" ]]; then
        install \
          --directory \
          --mode 0750 \
          "$repository/hooks/post-receive.d"
        destination="$repository/hooks/post-receive.d/publish"
        temporary="$repository/hooks/post-receive.d/.publish.$BASHPID"
        ln --force --no-dereference --symbolic \
          ${lib.escapeShellArg (lib.getExe hook)} \
          "$temporary"
        mv --force --no-target-directory "$temporary" "$destination"

        revision=$(git --git-dir "$repository" rev-parse --verify refs/heads/main 2>/dev/null || true)
        if [[ -n "$revision" ]] && ! ${lib.escapeShellArg (lib.getExe hook)} "$revision"; then
          status=1
        fi
      fi
    '') hooks
    + ''
      exit "$status"
    '';
  };
in
{
  nix.settings.extra-allowed-users = [ user ];

  # Publication hooks inherit Gitea's strict filesystem sandbox.
  systemd.services.gitea.serviceConfig.ReadWritePaths = [ publicationRoot ];

  systemd.tmpfiles.rules = [
    "d ${publicationRoot} 0755 ${user} nginx - -"
  ]
  ++ lib.mapAttrsToList (name: _: "d ${publicationRoot}/${name} 0755 ${user} nginx - -") publications
  ++ lib.mapAttrsToList (
    name: _: "d ${publicationRoot}/${name}/releases 0755 ${user} nginx - -"
  ) publications;

  systemd.services.gitea-publication-hooks = {
    description = "Install and reconcile Gitea publications";
    after = [ "gitea.service" ];
    environment.XDG_CACHE_HOME = "/var/cache/gitea-publications";
    requires = [ "gitea.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      ExecStart = lib.getExe installHooks;
      CacheDirectory = "gitea-publications";
      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        publicationRoot
        repositoryRoot
      ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.timers.gitea-publication-hooks = {
    description = "Retry and discover Gitea publications";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
