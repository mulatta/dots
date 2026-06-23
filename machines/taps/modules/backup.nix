{
  config,
  pkgs,
  ...
}:
let
  # Reproduce the config the stalwart service runs with (the module's own
  # configFile is a private let-binding) so --export reads the configured
  # stores. It is a pure toml render of services.stalwart.settings.
  stalwartConfig = (pkgs.formats.toml { }).generate "stalwart.toml" config.services.stalwart.settings;
in
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
    rustic-backup-files-kanidm.after = [ "kanidm.service" ];
    rustic-backup-files-route96.after = [ "route96-db-backup.service" ];

    # Stalwart's own export captures ALL stores -- the PostgreSQL data plus the
    # local RocksDB settings/queue that a raw pg_dump of stalwart-mail misses.
    # Runs online (no downtime); stages to /var/backup/stalwart for rustic.
    stalwart-export = {
      description = "Stalwart full store export for backup";
      after = [ "stalwart-mail.service" ];
      startAt = "*-*-* 01:00:00";
      serviceConfig = {
        Type = "oneshot";
        User = "stalwart-mail";
        Group = "stalwart-mail";
        ExecStartPre = "${pkgs.findutils}/bin/find /var/backup/stalwart -mindepth 1 -delete";
        ExecStart = "${config.services.stalwart.package}/bin/stalwart --config=${stalwartConfig} --export /var/backup/stalwart";
      };
    };

    # Back up the export only after it finishes.
    rustic-backup-files-stalwart.after = [ "stalwart-export.service" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/backup/stalwart 0750 stalwart-mail stalwart-mail -"
  ];

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
      # PostgreSQL backup (all databases except those backed up another way)
      postgres.niks3 = {
        startAt = "*-*-* 00,06,12,18:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
        # stalwart-mail is captured more completely by the stalwart-export
        # service above (postgres data + the local RocksDB store), so skip its
        # redundant ~8 GB pg_dump here.
        excludeDatabases = [ "stalwart-mail" ];
      };

      # Kanidm backup directory (Kanidm already creates daily backups)
      files.kanidm = {
        startAt = "*-*-* 02:00:00";
        sources = [ "/var/backup/kanidm" ];
        useProfiles = [ "rustic" ];
      };

      # Route96 metadata only; blob files are bounded local cache-like state.
      files.route96 = {
        startAt = "*-*-* 02:15:00";
        sources = [ "/var/backup/route96" ];
        useProfiles = [ "rustic" ];
      };

      # Stalwart full export (see the stalwart-export service above) -> R2.
      # This replaces relying on the postgres dump alone, which misses the
      # RocksDB store; the postgres dump of stalwart-mail is now redundant.
      files.stalwart = {
        startAt = "*-*-* 02:45:00";
        sources = [ "/var/backup/stalwart" ];
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
