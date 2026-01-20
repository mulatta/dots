{
  config,
  pkgs,
  ...
}:
{
  imports = [ ../../../nixosModules/rustic ];
  # Rustic password secret generator (per-machine, different repos)
  clan.core.vars.generators.rustic = {
    files."password.txt" = {
      secret = true;
      owner = "rustic";
      group = "rustic";
    };

    runtimeInputs = [ pkgs.openssl ];

    script = ''
      openssl rand -base64 32 > "$out/password.txt"
    '';
  };

  # Service-specific dependencies (rclone env is set in rustic module)
  systemd.services = {
    rustic-backup-sqlite-vaultwarden.after = [ "vaultwarden.service" ];
    rustic-backup-files-kanidm.after = [ "kanidm.service" ];
    rustic-backup-command-stalwart.after = [ "stalwart-mail.service" ];
  };

  services.rustic = {
    enable = true;

    profiles.rustic = {
      repository = {
        repository = "rclone:r2:backup/taps";
        password-file = config.clan.core.vars.generators.rustic.files."password.txt".path;
      };
      backup.host = "taps";
    };

    backups = {
      # PostgreSQL backup (niks3 database) - weekly
      postgres.niks3 = {
        startAt = "Mon *-*-* 02:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
      };

      # Vaultwarden SQLite database - every 6 hours (critical)
      sqlite.vaultwarden = {
        startAt = "*-*-* 00,06,12,18:00:00";
        database = "/var/lib/vaultwarden/db.sqlite3";
        backupName = "vaultwarden.sqlite3";
        tempPath = "/var/lib/vaultwarden";
        useProfiles = [ "rustic" ];
      };

      # Kanidm backup directory (Kanidm already creates daily backups)
      files.kanidm = {
        startAt = "*-*-* 02:00:00";
        sources = [ "/var/backup/kanidm" ];
        useProfiles = [ "rustic" ];
      };

      # Stalwart Mail RocksDB data
      # Stop service for consistent backup, then restart
      commands.stalwart = {
        startAt = "*-*-* 02:30:00";
        command = "${pkgs.writeScript "stalwart-backup" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail
          systemctl stop stalwart-mail
          trap "systemctl start stalwart-mail" EXIT
          tar -cf - -C /var/lib/stalwart-mail data
        ''}";
        filename = "/stalwart/data.tar";
        useProfiles = [ "rustic" ];
      };
    };

    prune = {
      enable = true;
      startAt = "Sun *-*-* 03:00:00";
      useProfiles = [ "rustic" ];
    };

    check = {
      enable = true;
      startAt = "*-*-01 03:30:00";
      useProfiles = [ "rustic" ];
    };
  };
}
