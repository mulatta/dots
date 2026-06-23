{
  config,
  pkgs,
  ...
}:
{
  imports = [ ../../../nixosModules/rustic ];
  # Rustic password secret generator (per-machine, different repos)
  clan.core.vars.generators = {
    rustic = {
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

    # Dedicated R2 key for the append-only mail blob copy. This must be
    # separate from both Stalwart's primary bucket key and rustic's backup key:
    # Stalwart must not be able to mutate the backup bucket, and rustic's
    # general backup key must not gain access to mail bodies.
    stalwart-r2-copy = {
      files."rclone.conf" = {
        secret = true;
        owner = "rustic";
        group = "rustic";
      };
      prompts."access-key-id" = {
        description = "R2 access key ID that can read mail-blobs and write mail-blobs-backup";
        type = "hidden";
      };
      prompts."secret-access-key" = {
        description = "R2 secret access key that can read mail-blobs and write mail-blobs-backup";
        type = "hidden";
      };
      script = ''
        cat > "$out/rclone.conf" <<EOF
        [mail-blobs-copy]
        type = s3
        provider = Cloudflare
        access_key_id = $(tr -d '\r\n' < "$prompts/access-key-id")
        secret_access_key = $(tr -d '\r\n' < "$prompts/secret-access-key")
        endpoint = https://a36871be6860124304dfb5c3b3eb8c1a.r2.cloudflarestorage.com
        no_check_bucket = true
        EOF
      '';
    };
  };

  # Service-specific dependencies (rclone env is set in rustic module)
  systemd.services = {
    rustic-backup-files-kanidm.after = [ "kanidm.service" ];
    rustic-backup-files-route96.after = [ "route96-db-backup.service" ];

    # Append-only copy of the R2 blob store to the mail-blobs-backup bucket. R2
    # has no object versioning, so this is the recovery path if Stalwart's blob
    # GC (or a bug/compromised token) removes a live blob from mail-blobs:
    # "copy --ignore-existing" -- never "sync" -- only adds missing objects and
    # never propagates deletions, so the backup keeps blobs the primary dropped. A
    # dedicated rclone key reads mail-blobs and writes mail-blobs-backup; it is
    # intentionally separate from Stalwart's own token and rustic's backup key.
    mail-blobs-backup = {
      description = "Copy Stalwart R2 blobs to the backup bucket";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      startAt = "*-*-* 05:00:00";
      environment.RCLONE_CONFIG =
        config.clan.core.vars.generators.stalwart-r2-copy.files."rclone.conf".path;
      serviceConfig = {
        Type = "oneshot";
        User = "rustic";
        Group = "rustic";
        ExecStart = "${pkgs.rclone}/bin/rclone copy --s3-no-check-bucket --ignore-existing mail-blobs-copy:mail-blobs mail-blobs-copy:mail-blobs-backup";
      };
    };
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
      # PostgreSQL backup (all databases). Stalwart's blobs now live in R2, so
      # its database is small enough to dump here alongside the rest instead of
      # via a separate full-store export.
      postgres.niks3 = {
        startAt = "*-*-* 00,06,12,18:00:00";
        prefix = "/postgres";
        useProfiles = [ "rustic" ];
      };

      # Kanidm writes its own daily dump at 03:00; run after it (not before) so
      # the offsite copy contains the same day's dump rather than yesterday's.
      files.kanidm = {
        startAt = "*-*-* 03:30:00";
        sources = [ "/var/backup/kanidm" ];
        useProfiles = [ "rustic" ];
      };

      # Route96 metadata only; blob files are bounded local cache-like state.
      files.route96 = {
        startAt = "*-*-* 02:15:00";
        sources = [ "/var/backup/route96" ];
        useProfiles = [ "rustic" ];
      };

      # Vaultwarden data dir: attachments and the RSA key live on disk, not in
      # the PostgreSQL database (which the postgres backup covers). Small and
      # static, so a live copy is fine. Vaultwarden has no server-side export.
      files.vaultwarden = {
        startAt = "*-*-* 02:30:00";
        sources = [ "/var/lib/vaultwarden" ];
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
