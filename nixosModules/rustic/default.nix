{
  config,
  lib,
  pkgs,
  ...
}:

let
  tomlFormat = pkgs.formats.toml { };
  cfg = config.services.rustic;

  # Default settings applied to all profiles
  # - cache-dir: Use dedicated cache directory accessible by rustic user
  # - rclone-command: Skip bucket creation check (buckets provisioned by terraform)
  # - forget: Default retention policy
  defaultProfileSettings = {
    repository = {
      cache-dir = "/var/lib/rustic/cache";
      options.rclone-command = "rclone serve restic --addr localhost:0 --s3-no-check-bucket";
    };
    forget = {
      keep-daily = 7;
      keep-weekly = 4;
      keep-monthly = 6;
    };
  };

  # Merge defaults into each profile (user settings override defaults)
  mergedProfiles = lib.mapAttrs (_: v: lib.recursiveUpdate defaultProfileSettings v) cfg.profiles;

  # Generate TOML config files for each profile
  configFiles = lib.mapAttrs (k: v: tomlFormat.generate "rustic-${k}.toml" v) mergedProfiles;

  # Common backup options shared across all backup types
  commonBackupOptions = {
    startAt = lib.mkOption {
      type = with lib.types; either (listOf str) str;
      description = "Time(s) at which to run this backup. Format: man systemd.time";
    };

    useProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Config profiles to use";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments for rustic";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run the backup as (root recommended for file access)";
    };
  };

  # Build profile arguments string
  mkProfileArgs = profiles: lib.concatMapStrings (s: " -P \"${s}\"") profiles;

  # Build extra arguments string
  mkExtraArgs = args: lib.concatMapStrings (s: " \"${s}\"") args;

  # Create backup script for files backup
  mkFilesBackupScript =
    name: backup:
    let
      profileArgs = mkProfileArgs backup.useProfiles;
      extraArgs = mkExtraArgs backup.extraArgs;
      sourcesArgs = lib.concatMapStrings (s: " \"${s}\"") backup.sources;
      asPathArg = lib.optionalString (backup.asPath != null) " --as-path \"${backup.asPath}\"";
    in
    pkgs.writeScript "rustic-backup-files-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${cfg.package}/bin/rustic backup${sourcesArgs}${asPathArg}${profileArgs}${extraArgs}
    '';

  # Create backup script for command backup
  mkCommandBackupScript =
    name: backup:
    let
      profileArgs = mkProfileArgs backup.useProfiles;
      extraArgs = mkExtraArgs backup.extraArgs;
      filenameArg = lib.optionalString (
        backup.filename != null
      ) " --stdin-filename \"${backup.filename}\"";
    in
    pkgs.writeScript "rustic-backup-command-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${cfg.package}/bin/rustic backup --stdin-command "${backup.command}" -${filenameArg}${profileArgs}${extraArgs}
    '';

  # Create backup script for PostgreSQL backup
  mkPostgresBackupScript =
    name: _backup:
    let
      systemctl = "${config.systemd.package}/bin/systemctl";
    in
    pkgs.writeScript "rustic-backup-postgres-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      # Start globals backup
      ${systemctl} start --no-block rustic-postgres-globals-${name}.service

      # Get list of databases and start backup for each
      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/psql \
        -c 'SELECT datname FROM pg_database WHERE datistemplate = false' \
        --csv \
        | tail -n +2 \
        | xargs -I {} ${systemctl} start --no-block rustic-postgres-db-${name}@{}.service
    '';

  # Create globals backup script for PostgreSQL
  mkPostgresGlobalsScript =
    name: backup:
    let
      profileArgs = mkProfileArgs backup.useProfiles;
      extraArgs = mkExtraArgs backup.extraArgs;
    in
    pkgs.writeScript "rustic-postgres-globals-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/pg_dumpall --globals-only \
        | ${cfg.package}/bin/rustic backup \
          --stdin-filename "${backup.prefix}/globals.sql" \
          -${profileArgs}${extraArgs}
    '';

  # Create per-database backup script for PostgreSQL
  mkPostgresDbScript =
    name: backup:
    let
      profileArgs = mkProfileArgs backup.useProfiles;
      extraArgs = mkExtraArgs backup.extraArgs;
    in
    pkgs.writeScript "rustic-postgres-db-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      DB_NAME="$1"
      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/pg_dump "$DB_NAME" \
        | ${cfg.package}/bin/rustic backup \
          --stdin-filename "${backup.prefix}/db/$DB_NAME.sql" \
          -${profileArgs}${extraArgs}
    '';

  # Create backup script for SQLite backup
  mkSqliteBackupScript =
    name: backup:
    let
      profileArgs = mkProfileArgs backup.useProfiles;
      extraArgs = mkExtraArgs backup.extraArgs;
      backupName = if backup.backupName != null then backup.backupName else baseNameOf backup.database;
    in
    pkgs.writeScript "rustic-backup-sqlite-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${pkgs.sqlite}/bin/sqlite3 "${backup.database}" ".backup '${backup.tempPath}/${backupName}'"
      ${cfg.package}/bin/rustic backup "${backup.tempPath}/${backupName}"${profileArgs}${extraArgs}
      rm -f "${backup.tempPath}/${backupName}"
    '';

in
{
  options.services.rustic = {
    enable = lib.mkEnableOption "rustic backup service";

    package = lib.mkPackageOption pkgs "rustic" { };

    profiles = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      description = ''
        Configuration profiles for rustic in TOML format.
        The `rustic` profile is used by default.

        WARNING: Do not put passwords here - they will be world-readable in the nix store.
        Instead, use a separate file and reference it with:
        ```nix
        global.use-profiles = ["/root/rustic-passwords"];
        ```
      '';
      example = lib.literalExpression ''
        {
          rustic = {
            repository = {
              repository = "rclone:r2:backup";
            };
            forget = {
              keep-daily = 7;
              keep-weekly = 4;
              keep-monthly = 6;
            };
          };
        }
      '';
    };

    backups = {
      files = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = commonBackupOptions // {
              sources = lib.mkOption {
                type = lib.types.listOf lib.types.path;
                description = "Paths to backup";
              };

              asPath = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Override the backup path in snapshot";
              };
            };
          }
        );
        default = { };
        description = "File-based backups";
      };

      commands = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = commonBackupOptions // {
              command = lib.mkOption {
                type = lib.types.str;
                description = "Command whose output will be backed up";
              };

              filename = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Filename to use in the backup";
              };
            };
          }
        );
        default = { };
        description = "Command output backups";
      };

      postgres = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = commonBackupOptions // {
              prefix = lib.mkOption {
                type = lib.types.str;
                default = "/postgres";
                description = "Path prefix for dumps in the backup";
              };
            };
          }
        );
        default = { };
        description = "PostgreSQL database backups (all databases)";
      };

      sqlite = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = commonBackupOptions // {
              database = lib.mkOption {
                type = lib.types.path;
                description = "Path to the SQLite database file";
              };

              backupName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Name for the backup file (defaults to database filename)";
              };

              tempPath = lib.mkOption {
                type = lib.types.path;
                default = "/tmp";
                description = "Temporary path for the backup file before uploading";
              };
            };
          }
        );
        default = { };
        description = "SQLite database backups";
      };
    };

    prune = {
      enable = lib.mkEnableOption "automatic pruning of old backups";

      startAt = lib.mkOption {
        type = with lib.types; either (listOf str) str;
        default = "weekly";
        description = "When to run the prune job";
      };

      useProfiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Config profiles to use for pruning";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments for the prune command";
      };
    };

    check = {
      enable = lib.mkEnableOption "periodic repository checks";

      startAt = lib.mkOption {
        type = with lib.types; either (listOf str) str;
        default = "monthly";
        description = "When to run the check job";
      };

      useProfiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Config profiles to use for checking";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments for the check command";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Dedicated user/group for running backups
    users.groups.rustic = { };
    users.users.rustic = {
      isSystemUser = true;
      group = "rustic";
      home = "/var/lib/rustic";
      createHome = true;
    };

    environment.systemPackages = [
      cfg.package
      pkgs.rclone
    ];

    # Shared rclone R2 credentials (prompted once, shared across machines)
    clan.core.vars.generators.rclone-r2 = {
      share = true;

      files."rclone.conf" = {
        secret = true;
        owner = "rustic";
        group = "rustic";
      };

      prompts.r2_access_key_id = {
        description = "R2 Access Key ID from Cloudflare Dashboard";
        type = "line";
        persist = true;
      };
      prompts.r2_secret_access_key = {
        description = "R2 Secret Access Key from Cloudflare Dashboard";
        type = "hidden";
        persist = true;
      };
      prompts.r2_account_id = {
        description = "Cloudflare Account ID";
        type = "line";
        persist = true;
      };

      script = ''
        cat > "$out/rclone.conf" << EOF
        [r2]
        type = s3
        provider = Cloudflare
        access_key_id = $(cat "$prompts/r2_access_key_id")
        secret_access_key = $(cat "$prompts/r2_secret_access_key")
        endpoint = https://$(cat "$prompts/r2_account_id").r2.cloudflarestorage.com
        acl = private
        EOF
      '';
    };

    # Install rclone config and profile config files
    environment.etc = {
      "rclone/rclone.conf".source = config.clan.core.vars.generators.rclone-r2.files."rclone.conf".path;
    }
    // lib.mapAttrs' (k: v: {
      name = "rustic/${k}.toml";
      value.source = v;
    }) configFiles;

    systemd.services =
      let
        rcloneEnv = {
          RCLONE_CONFIG = "/etc/rclone/rclone.conf";
        };
        rclonePath = [ pkgs.rclone ];
      in
      # Repository initialization service
      {
        "rustic-init" = {
          description = "Initialize rustic repository";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "rustic";
          };
          script = ''
            # Try to initialize; if already initialized, that's fine
            output=$(${cfg.package}/bin/rustic init 2>&1) && {
              echo "Repository initialized successfully"
            } || {
              if echo "$output" | grep -q "Config file already exists"; then
                echo "Repository already initialized"
              else
                echo "$output" >&2
                exit 1
              fi
            }
          '';
        };
      }
      # Files backups
      // lib.mapAttrs' (name: backup: {
        name = "rustic-backup-files-${name}";
        value = {
          description = "Rustic files backup: ${name}";
          after = [ "rustic-init.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = backup.user;
            ExecStart = "${mkFilesBackupScript name backup}";
          };
          startAt = backup.startAt;
        };
      }) cfg.backups.files
      # Command backups
      // lib.mapAttrs' (name: backup: {
        name = "rustic-backup-command-${name}";
        value = {
          description = "Rustic command backup: ${name}";
          after = [ "rustic-init.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = backup.user;
            ExecStart = "${mkCommandBackupScript name backup}";
          };
          startAt = backup.startAt;
        };
      }) cfg.backups.commands
      # PostgreSQL backups (main service + globals + per-db template)
      // lib.concatMapAttrs (name: backup: {
        "rustic-backup-postgres-${name}" = {
          description = "Rustic PostgreSQL backup: ${name}";
          after = [
            "rustic-init.service"
            "postgresql.service"
          ];
          requires = [ "postgresql.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            ExecStart = "${mkPostgresBackupScript name backup}";
          };
          startAt = backup.startAt;
        };
        "rustic-postgres-globals-${name}" = {
          description = "Rustic PostgreSQL globals backup: ${name}";
          after = [
            "rustic-init.service"
            "postgresql.service"
          ];
          requires = [ "postgresql.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            ExecStart = "${mkPostgresGlobalsScript name backup}";
          };
        };
        "rustic-postgres-db-${name}@" = {
          description = "Rustic PostgreSQL database backup: ${name} (%i)";
          after = [
            "rustic-init.service"
            "postgresql.service"
          ];
          requires = [ "postgresql.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            ExecStart = "${mkPostgresDbScript name backup} %i";
          };
        };
      }) cfg.backups.postgres
      # SQLite backups
      // lib.mapAttrs' (name: backup: {
        name = "rustic-backup-sqlite-${name}";
        value = {
          description = "Rustic SQLite backup: ${name}";
          after = [ "rustic-init.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = backup.user;
            ExecStart = "${mkSqliteBackupScript name backup}";
          };
          startAt = backup.startAt;
        };
      }) cfg.backups.sqlite
      # Prune service
      // lib.optionalAttrs cfg.prune.enable {
        "rustic-prune" = {
          description = "Rustic prune old backups";
          after = [ "rustic-init.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = "rustic";
            ExecStart =
              let
                profileArgs = mkProfileArgs cfg.prune.useProfiles;
                extraArgs = mkExtraArgs cfg.prune.extraArgs;
              in
              "${cfg.package}/bin/rustic forget --prune${profileArgs}${extraArgs}";
          };
          startAt = cfg.prune.startAt;
        };
      }
      # Check service
      // lib.optionalAttrs cfg.check.enable {
        "rustic-check" = {
          description = "Rustic repository check";
          after = [ "rustic-init.service" ];
          environment = rcloneEnv;
          path = rclonePath;
          serviceConfig = {
            Type = "oneshot";
            User = "rustic";
            ExecStart =
              let
                profileArgs = mkProfileArgs cfg.check.useProfiles;
                extraArgs = mkExtraArgs cfg.check.extraArgs;
              in
              "${cfg.package}/bin/rustic check${profileArgs}${extraArgs}";
          };
          startAt = cfg.check.startAt;
        };
      };
  };
}
