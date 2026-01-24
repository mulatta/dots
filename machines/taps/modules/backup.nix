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
    rustic-backup-files-kanidm.after = [ "kanidm.service" ];
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
      # PostgreSQL backup (all databases) - every 6 hours
      postgres.niks3 = {
        startAt = "*-*-* 00,06,12,18:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
      };

      # Kanidm backup directory (Kanidm already creates daily backups)
      files.kanidm = {
        startAt = "*-*-* 02:00:00";
        sources = [ "/var/backup/kanidm" ];
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
