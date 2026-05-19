{
  config,
  pkgs,
  lib,
  ...
}:
let
  route96 = pkgs.callPackage ../../../packages/route96 { };
  port = 8396;
  domain = "blossom.mulatta.io";
  publicUrl = "https://${domain}";
  dataDir = "/var/lib/route96";
  filesDir = "${dataDir}/files";
  imagePath = "${dataDir}-files.img";
  maxUploadBytes = 104857600;
  hardLimitBytes = 10 * 1024 * 1024 * 1024;
  gcTriggerBytes = 8 * 1024 * 1024 * 1024;
  gcTargetBytes = 6 * 1024 * 1024 * 1024;
  whitelistPubkeys = lib.filter (pubkey: pubkey != null && pubkey != "") (
    map (identity: identity.pubkey) (builtins.attrValues config.mulatta.nostr.identities)
  );
  whitelistFile = pkgs.writeText "route96-whitelist.txt" (
    builtins.concatStringsSep "\n" whitelistPubkeys + "\n"
  );
  configFile = pkgs.writeText "route96-config.yaml" ''
    listen: "127.0.0.1:${toString port}"
    database: "mysql://route96@localhost/route96?socket=/run/mysqld/mysqld.sock"
    storage_dir: "${filesDir}"
    max_upload_bytes: ${toString maxUploadBytes}
    public_url: "${publicUrl}"
    delete_unaccessed_days: 90
    whitelist: "${whitelistFile}"
  '';
  storageSetup = pkgs.writeShellApplication {
    name = "route96-storage-setup";
    runtimeInputs = with pkgs; [
      coreutils
      e2fsprogs
      util-linux
    ];
    text = ''
      set -euo pipefail

      install -d -m 0755 -o route96 -g route96 ${dataDir}
      install -d -m 0755 ${filesDir}

      if [ ! -e ${imagePath} ]; then
        truncate -s ${toString hardLimitBytes} ${imagePath}
        chmod 0600 ${imagePath}
      fi

      if ! blkid -o value -s TYPE ${imagePath} >/dev/null 2>&1; then
        mkfs.ext4 -F -L route96-files ${imagePath}
      fi

      if ! mountpoint -q ${filesDir}; then
        mount -o loop,nosuid,nodev,noexec ${imagePath} ${filesDir}
      fi

      chown route96:route96 ${filesDir}
    '';
  };
  pressureGc = pkgs.writeShellApplication {
    name = "route96-pressure-gc";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      gnugrep
      mariadb
    ];
    text = ''
      set -euo pipefail

      mysql_route96() {
        mariadb --batch --raw --skip-column-names --socket=/run/mysqld/mysqld.sock route96 "$@"
      }

      schema_ready() {
        [ "$(mysql_route96 --execute="select count(*) from information_schema.tables where table_schema = database() and table_name = 'uploads'")" = 1 ]
      }

      total_bytes() {
        mysql_route96 --execute='select cast(coalesce(sum(size), 0) as unsigned) from uploads where banned = false'
      }

      file_path() {
        local id="$1"
        local lower
        lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
        printf '%s/%s/%s/%s\n' "${filesDir}" "''${lower:0:2}" "''${lower:2:2}" "$lower"
      }

      if ! schema_ready; then
        echo "route96 schema is not migrated yet; skipping pressure GC"
        exit 0
      fi

      current=$(total_bytes)
      if [ "$current" -lt ${toString gcTriggerBytes} ]; then
        echo "route96 usage $current bytes is below trigger ${toString gcTriggerBytes}"
        exit 0
      fi

      echo "route96 usage $current bytes reached trigger ${toString gcTriggerBytes}; pruning to ${toString gcTargetBytes}"

      while [ "$current" -gt ${toString gcTargetBytes} ]; do
        candidates=$(mysql_route96 --execute="
          select hex(u.id), cast(u.size as unsigned)
          from uploads u
          left join file_stats fs on fs.file = u.id
          where u.banned = false
          order by
            (coalesce(fs.egress_bytes, 0) = 0) desc,
            (fs.last_accessed is null) desc,
            coalesce(fs.last_accessed, u.created) asc,
            u.created asc
          limit 100
        ")

        if [ -z "$candidates" ]; then
          echo "no prune candidates left"
          exit 0
        fi

        deleted=0
        while IFS=$'\t' read -r id size; do
          [ -n "$id" ] || continue
          path=$(file_path "$id")

          mysql_route96 --execute="
            delete from user_uploads where file = unhex('$id');
            delete from uploads where id = unhex('$id');
          "
          rm -f -- "$path"

          current=$(( current - size ))
          deleted=$(( deleted + 1 ))
          echo "pruned $id ($size bytes); estimated usage $current"

          if [ "$current" -le ${toString gcTargetBytes} ]; then
            break
          fi
        done <<< "$candidates"

        if [ "$deleted" -eq 0 ]; then
          echo "failed to delete any prune candidates"
          exit 1
        fi
      done
    '';
  };
in
{
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = [ "route96" ];
    ensureUsers = [
      {
        name = "route96";
        ensurePermissions."route96.*" = "ALL PRIVILEGES";
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 route96 route96 - -"
    "d /var/backup/route96 0750 route96 route96 - -"
  ];

  systemd.services.route96-storage = {
    description = "Route96 bounded file storage";
    before = [ "route96.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${storageSetup}/bin/route96-storage-setup";
      ExecStop = "${pkgs.util-linux}/bin/umount ${filesDir}";
    };
  };

  systemd.services.route96 = {
    description = "Route96 Nostr blob storage";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "mysql.service"
      "route96-storage.service"
    ];
    requires = [
      "mysql.service"
      "route96-storage.service"
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${route96}/bin/route96 --config ${configFile}";
      Restart = "on-failure";
      RestartSec = 5;
      WorkingDirectory = "${route96}/share/route96";

      StateDirectory = "route96";
      User = "route96";
      Group = "route96";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ReadWritePaths = [ dataDir ];
    };
  };

  systemd.services.route96-db-backup = {
    description = "Route96 database backup dump";
    after = [ "mysql.service" ];
    requires = [ "mysql.service" ];
    path = with pkgs; [
      gzip
      mariadb
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "route96";
      Group = "route96";
    };
    script = ''
      set -euo pipefail
      tmp=$(mktemp /var/backup/route96/route96.sql.gz.XXXXXX)
      mariadb-dump --single-transaction --socket=/run/mysqld/mysqld.sock route96 | gzip -9 > "$tmp"
      chmod 0640 "$tmp"
      mv "$tmp" /var/backup/route96/route96.sql.gz
    '';
  };

  systemd.timers.route96-db-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      Persistent = true;
      Unit = "route96-db-backup.service";
    };
  };

  systemd.services.route96-pressure-gc = {
    description = "Route96 pressure garbage collection";
    after = [
      "mysql.service"
      "route96-storage.service"
      "route96.service"
    ];
    requires = [
      "mysql.service"
      "route96-storage.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pressureGc}/bin/route96-pressure-gc";
      User = "route96";
      Group = "route96";
    };
  };

  systemd.timers.route96-pressure-gc = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "15min";
      AccuracySec = "1min";
      Unit = "route96-pressure-gc.service";
    };
  };

  users.users.route96 = {
    isSystemUser = true;
    group = "route96";
  };
  users.groups.route96 = { };

  services.nginx.appendHttpConfig = lib.mkAfter ''
    limit_req_zone $binary_remote_addr zone=blossom_upload:10m rate=2r/m;
    limit_conn_zone $binary_remote_addr zone=blossom_conn:10m;
  '';

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = ''
          client_max_body_size 100m;
          proxy_request_buffering on;
          proxy_read_timeout 300s;
        '';
      };

      "~ ^/(upload|media|nip96|api/upload)" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = ''
          limit_req zone=blossom_upload burst=4 nodelay;
          limit_conn blossom_conn 2;
          client_max_body_size 100m;
          proxy_request_buffering on;
          proxy_read_timeout 300s;
        '';
      };
    };
  };
}
