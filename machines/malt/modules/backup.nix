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
      # PostgreSQL backups (n8n, nextcloud) - daily
      # All databases backed up together; rustic deduplicates unchanged data
      postgres.all = {
        startAt = "*-*-* 02:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
      };

      # Minecraft worlds -> R2 (offsite). Backed up from a ZFS snapshot taken
      # right before the run (see the systemd hooks below), so the world is a
      # consistent point-in-time rather than a live mid-write copy. ZFS
      # auto-snapshots still cover local recovery; this is the offsite copy.
      files.minecraft = {
        sources = [ "/var/lib/minecraft/.zfs/snapshot/rustic" ];
        asPath = "/var/lib/minecraft"; # store under the real path, not the snapshot path
        startAt = "*-*-* 04:00:00";
        useProfiles = [ "rustic" ];
      };

      # Media files (nextcloud data) excluded from backup
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

  # Take a fresh ZFS snapshot right before the Minecraft backup so rustic reads
  # a consistent point-in-time, and drop it afterwards. The leading "-" on the
  # destroy steps ignores a missing snapshot (e.g. a previous crashed run).
  systemd.services."rustic-backup-files-minecraft".serviceConfig = {
    ExecStartPre = [
      "-${pkgs.zfs}/bin/zfs destroy zroot/minecraft@rustic"
      "${pkgs.zfs}/bin/zfs snapshot zroot/minecraft@rustic"
    ];
    ExecStartPost = "-${pkgs.zfs}/bin/zfs destroy zroot/minecraft@rustic";
  };
}
