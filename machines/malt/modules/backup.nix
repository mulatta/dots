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

  services.rustic = {
    enable = true;

    profiles.rustic = {
      repository = {
        repository = "rclone:r2:backup/malt";
        password-file = config.clan.core.vars.generators.rustic.files."password.txt".path;
      };
      backup.host = "malt";
    };

    backups = {
      # PostgreSQL backups (n8n, nextcloud, immich) - daily
      # All databases backed up together; rustic deduplicates unchanged data
      postgres.all = {
        startAt = "*-*-* 02:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
      };

      # Media files (nextcloud data, immich) excluded from backup
      # Rely on ZFS snapshots for local redundancy
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
