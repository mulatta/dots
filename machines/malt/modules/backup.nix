{
  config,
  pkgs,
  ...
}:
let
  snapshotName = job: "rustic-${job}";
  snapshotPath = job: path: "/.zfs/snapshot/${snapshotName job}${path}";
  snapshotHooks = job: {
    ExecStartPre = [
      "-${pkgs.zfs}/bin/zfs destroy zroot/root/nixos@${snapshotName job}"
      "${pkgs.zfs}/bin/zfs snapshot zroot/root/nixos@${snapshotName job}"
    ];
    ExecStartPost = [
      "-${pkgs.zfs}/bin/zfs destroy zroot/root/nixos@${snapshotName job}"
    ];
  };
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
        sources = [ (snapshotPath "minecraft" "/var/lib/minecraft") ];
        asPath = "/var/lib/minecraft"; # store under the real path, not the snapshot path
        startAt = "*-*-* 04:00:00";
        useProfiles = [ "rustic" ];
      };

      # Nextcloud data -> R2 (offsite), from a ZFS snapshot for a consistent
      # point-in-time. The Nextcloud database is already covered by the
      # postgres backup above; this adds the data files.
      files.nextcloud = {
        sources = [ (snapshotPath "nextcloud" "/var/lib/nextcloud") ];
        asPath = "/var/lib/nextcloud";
        startAt = "*-*-* 04:30:00";
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

  # Distinct names prevent overlapping jobs from replacing each other's root
  # snapshot after unification. Leading "-" tolerates cleanup after a crash.
  systemd.services."rustic-backup-files-minecraft".serviceConfig = snapshotHooks "minecraft";

  systemd.services."rustic-backup-files-nextcloud".serviceConfig = snapshotHooks "nextcloud";
}
