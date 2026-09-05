{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
  };

  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    compression = "zstd";
  };

  environment.systemPackages = [
    (
      let
        oldPostgres = pkgs.postgresql_16;
        # Specify the PostgreSQL package to upgrade to and include required extensions.
        newPostgres = pkgs.postgresql_17.withPackages (_pp: [ ]);
        cfg = config.services.postgresql;
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" ''
        set -eux
        # Stop dependent services before invoking this manual migration helper.
        systemctl stop postgresql

        export NEWDATA="/var/lib/postgresql/${newPostgres.psqlSchema}"
        export NEWBIN="${newPostgres}/bin"
        export OLDDATA="/var/lib/postgresql/${oldPostgres.psqlSchema}"
        export OLDBIN="${oldPostgres}/bin"

        install -d -m 0700 -o postgres -g postgres "$NEWDATA"
        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" -D "$NEWDATA" ${lib.escapeShellArgs cfg.initdbArgs}

        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir "$OLDDATA" --new-datadir "$NEWDATA" \
          --old-bindir "$OLDBIN" --new-bindir "$NEWBIN" \
          "$@"
      ''
    )
  ];
}
