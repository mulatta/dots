{
  config,
  pkgs,
  ...
}:
let
  domain = "dolt.mulatta.io";
  dataDir = "/var/lib/dolt";
  port = 3307;
  bootstrapPort = 13307;
  credentials = config.clan.core.vars.generators.dolt.files;

  bootstrap = pkgs.writeShellApplication {
    name = "dolt-bootstrap";
    runtimeInputs = [
      pkgs.dolt
      pkgs.mariadb.client
      pkgs.netcat
    ];
    text = ''
      dolt sql-server \
        --host 127.0.0.1 \
        --port ${toString bootstrapPort} \
        --data-dir ${dataDir} \
        --doltcfg-dir ${dataDir}/.doltcfg \
        --privilege-file ${dataDir}/.doltcfg/privileges.db \
        --branch-control-file ${dataDir}/.doltcfg/branch_control.db &
      server_pid=$!
      trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT

      ready=0
      for _ in $(seq 1 50); do
        if nc -z 127.0.0.1 ${toString bootstrapPort}; then
          ready=1
          break
        fi
        sleep 0.1
      done
      if [ "$ready" -ne 1 ]; then
        echo 'Dolt bootstrap server failed to become ready' >&2
        exit 1
      fi

      admin_password=$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/admin-password")
      client_password=$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/client-password")
      root_config=$(mktemp)
      chmod 600 "$root_config"
      {
        printf '[client]\nuser=root\npassword='
        printf '%s' "$admin_password"
        printf '\n'
      } > "$root_config"

      root_auth=()
      if ! mariadb --skip-ssl --protocol=tcp --host=127.0.0.1 --port=${toString bootstrapPort} --user=root --execute='SELECT 1' >/dev/null 2>&1; then
        root_auth=(--defaults-extra-file="$root_config")
      fi

      printf '%s\n' \
        "CREATE USER IF NOT EXISTS 'beads'@'%' IDENTIFIED BY '$client_password';" \
        "ALTER USER 'beads'@'%' IDENTIFIED BY '$client_password';" \
        "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'beads'@'%';" \
        "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, REFERENCES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, TRIGGER, EVENT ON *.* TO 'beads'@'%';" \
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '$admin_password';" \
        'FLUSH PRIVILEGES;' \
        | mariadb "''${root_auth[@]}" --skip-ssl --protocol=tcp --host=127.0.0.1 --port=${toString bootstrapPort} --user=root

      rm -f "$root_config"
    '';
  };
in
{
  clan.core.vars.generators.dolt = {
    files.admin-password = {
      secret = true;
      owner = "dolt";
    };
    files.client-password = {
      secret = true;
      owner = "dolt";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/admin-password"
      openssl rand -hex 32 > "$out/client-password"
    '';
  };

  services.dolt = {
    enable = true;
    inherit dataDir;
    settings = {
      behavior.auto_gc_behavior = {
        enable = true;
        archive_level = 1;
      };
      listener = {
        host = "0.0.0.0";
        inherit port;
        require_secure_transport = true;
        tls_cert = "/var/lib/acme/${domain}/fullchain.pem";
        tls_key = "/var/lib/acme/${domain}/key.pem";
      };
    };
  };

  users.users.dolt.extraGroups = [ "nginx" ];

  disko.devices.zpool.zroot.datasets."dolt" = {
    type = "zfs_fs";
    mountpoint = dataDir;
    options = {
      compression = "lz4";
      recordsize = "16K";
      "com.sun:auto-snapshot" = "true";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."/".return = "404";
  };

  security.acme.certs.${domain}.reloadServices = [ "dolt.service" ];

  systemd.services = {
    dolt-bootstrap = {
      description = "Initialize Dolt SQL credentials";
      after = [ "local-fs.target" ];
      before = [ "dolt.service" ];
      requiredBy = [ "dolt.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "dolt";
        Group = "dolt";
        LoadCredential = [
          "admin-password:${credentials.admin-password.path}"
          "client-password:${credentials.client-password.path}"
        ];
        ExecStart = "${bootstrap}/bin/dolt-bootstrap";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ dataDir ];
      };
    };

    dolt = {
      after = [
        "acme-finished-${domain}.target"
        "dolt-bootstrap.service"
      ];
      requires = [ "dolt-bootstrap.service" ];
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
