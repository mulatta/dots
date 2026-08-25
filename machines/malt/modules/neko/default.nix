{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;

  maltNeko = {
    wireguardAddress = "${wgPrefix}:${maltSuffix}";

    ports = {
      ui = {
        host = 8082;
        container = 8080;
      };
      media = 59000;
    };

    paths = {
      state = "/var/lib/neko";
      profile = "/var/lib/neko/chrome-profile";
    };

    image = self.packages.${pkgs.stdenv.hostPlatform.system}.neko-image;
  };

  inherit (maltNeko.paths) profile state;

  clearStaleChromiumProcessLocks = pkgs.writeShellScript "neko-clear-stale-chromium-process-locks" ''
    # The previous container is gone, so persistent locks can only refer to dead runtime state.
    rm -f \
      ${profile}/SingletonCookie \
      ${profile}/SingletonLock \
      ${profile}/SingletonSocket
  '';
in
{
  imports = [ ./runtime.nix ];

  _module.args.maltNeko = maltNeko;

  clan.core.vars.generators.neko = {
    files = {
      env.secret = true;
      user-password = {
        secret = true;
        deploy = false;
      };
      admin-password = {
        secret = true;
        deploy = false;
      };
    };
    files.env.restartUnits = [ "podman-neko.service" ];
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      set -euo pipefail

      openssl rand -hex 24 > "$out/user-password"
      openssl rand -hex 24 > "$out/admin-password"
      {
        printf 'NEKO_MEMBER_MULTIUSER_USER_PASSWORD=%s\n' "$(cat "$out/user-password")"
        printf 'NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD=%s\n' "$(cat "$out/admin-password")"
      } > "$out/env"
    '';
  };

  # Browser cookies are credentials, so this dataset intentionally stays out
  # of automatic snapshots and offsite backup.
  disko.devices.zpool.zroot.datasets.neko = {
    type = "zfs_fs";
    mountpoint = state;
    options = {
      compression = "lz4";
      "com.sun:auto-snapshot" = "false";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${state} 0700 1000 1000 -"
    "d ${profile} 0700 1000 1000 -"
  ];

  systemd.services.podman-neko = {
    after = [ "systemd-tmpfiles-setup.service" ];
    # OCI pre-start removes the old container before persistent process locks are cleared.
    serviceConfig.ExecStartPre = lib.mkAfter [ clearStaleChromiumProcessLocks ];
    unitConfig = {
      AssertPathIsMountPoint = state;
      RequiresMountsFor = [ state ];
    };
  };
}
