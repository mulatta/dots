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
  # - rclone-command: Skip bucket creation check (buckets provisioned by terraform)
  # - forget: Default retention policy
  defaultProfileSettings = {
    repository = {
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

  configFiles = lib.mapAttrs (k: v: tomlFormat.generate "rustic-${k}.toml" v) mergedProfiles;

  mkProfileArgs = profiles: lib.concatMapStrings (s: " -P ${lib.escapeShellArg s}") profiles;

  mkExtraArgs = args: lib.concatMapStrings (s: " ${lib.escapeShellArg s}") args;

  cacheDirFor = user: "${cfg.cacheBaseDir}/${user}";

  mkCacheArgs = user: " --cache-dir ${lib.escapeShellArg (cacheDirFor user)}";

  mkRusticArgs =
    {
      useProfiles,
      cacheUser,
      extraArgs ? [ ],
    }:
    "${mkProfileArgs useProfiles}${mkCacheArgs cacheUser}${mkExtraArgs extraArgs}";

  mkFilesBackupScript =
    name: backup:
    let
      sourcesArgs = lib.concatMapStrings (s: " ${lib.escapeShellArg s}") backup.sources;
      asPathArg = lib.optionalString (
        backup.asPath != null
      ) " --as-path ${lib.escapeShellArg backup.asPath}";
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = backup.user;
      };
    in
    pkgs.writeScript "rustic-backup-files-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${cfg.package}/bin/rustic backup${sourcesArgs}${asPathArg}${rusticArgs}
    '';

  mkCommandBackupScript =
    name: backup:
    let
      commandArg = lib.escapeShellArg backup.command;
      filenameArg = lib.optionalString (
        backup.filename != null
      ) " --stdin-filename ${lib.escapeShellArg backup.filename}";
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = backup.user;
      };
    in
    pkgs.writeScript "rustic-backup-command-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      # --force: rustic 0.11.3 skips reading stdin when a parent snapshot
      # exists, silently producing 0-byte backups. Force a full read so stdin
      # is always consumed (chunk dedup against the repo still applies).
      ${cfg.package}/bin/rustic backup --force --stdin-command ${commandArg} -${filenameArg}${rusticArgs}
    '';

  mkPostgresBackupScript =
    name: backup:
    let
      systemctl = "${config.systemd.package}/bin/systemctl";
      systemdEscape = "${config.systemd.package}/bin/systemd-escape";
      databaseFilter =
        if backup.excludeDatabases == [ ] then
          "${pkgs.coreutils}/bin/tail -n +2"
        else
          "${pkgs.coreutils}/bin/tail -n +2 | ${pkgs.gawk}/bin/awk 'NR==FNR { exclude[$0]=1; next } !($0 in exclude)' ${pkgs.writeText "rustic-postgres-excluded-databases-${name}" (lib.concatLines backup.excludeDatabases)} -";
    in
    pkgs.writeScript "rustic-backup-postgres-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      ${systemctl} start rustic-postgres-globals-${name}.service

      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/psql \
        -c 'SELECT datname FROM pg_database WHERE datistemplate = false' \
        --csv \
        | ${databaseFilter} \
        | while IFS= read -r database; do
            unit=$(${systemdEscape} --template=rustic-postgres-db-${name}@.service "$database")
            ${systemctl} start "$unit"
          done
    '';

  mkPostgresGlobalsScript =
    name: backup:
    let
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = "root";
      };
    in
    pkgs.writeScript "rustic-postgres-globals-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/pg_dumpall --globals-only \
        | ${cfg.package}/bin/rustic backup \
          --force \
          --stdin-filename ${lib.escapeShellArg "${backup.prefix}/globals.sql"} \
          -${rusticArgs}
    '';

  mkPostgresDbScript =
    name: backup:
    let
      systemdEscape = "${config.systemd.package}/bin/systemd-escape";
      backupPrefix = lib.escapeShellArg backup.prefix;
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = "root";
      };
    in
    pkgs.writeScript "rustic-postgres-db-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      DB_NAME=$(${systemdEscape} --unescape "$1")
      BACKUP_PREFIX=${backupPrefix}
      ${pkgs.sudo}/bin/sudo -u postgres \
        ${config.services.postgresql.package}/bin/pg_dump "$DB_NAME" \
        | ${cfg.package}/bin/rustic backup \
          --force \
          --stdin-filename "$BACKUP_PREFIX/db/$DB_NAME.sql" \
          -${rusticArgs}
    '';

  mkSqliteBackupScript =
    name: backup:
    let
      backupName = if backup.backupName != null then backup.backupName else baseNameOf backup.database;
      backupPath = "${backup.tempPath}/${backupName}";
      sqliteBackupCommand = ".backup '${builtins.replaceStrings [ "'" ] [ "''" ] backupPath}'";
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = backup.user;
      };
    in
    pkgs.writeScript "rustic-backup-sqlite-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${pkgs.sqlite}/bin/sqlite3 ${lib.escapeShellArg backup.database} ${lib.escapeShellArg sqliteBackupCommand}
      ${cfg.package}/bin/rustic backup ${lib.escapeShellArg backupPath}${rusticArgs}
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg backupPath}
    '';

  backupUsers = lib.unique (
    [
      "root"
      "rustic"
    ]
    ++ lib.mapAttrsToList (_: backup: backup.user) cfg.backups.files
    ++ lib.mapAttrsToList (_: backup: backup.user) cfg.backups.commands
    ++ lib.mapAttrsToList (_: backup: backup.user) cfg.backups.sqlite
  );

  cacheDirRuleFor = user: "d ${cacheDirFor user} 0700 ${user} - - -";
in
{
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

    systemd.tmpfiles.rules = [
      "d ${cfg.cacheBaseDir} 0755 root root - -"
    ]
    ++ map cacheDirRuleFor backupUsers;

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
        maintenanceJobLimits = {
          Slice = "rustic-maintenance.slice";
          Nice = 19;
          IOSchedulingClass = "idle";
        };

        mkRusticService =
          {
            description,
            user,
            execStart,
            startAt ? null,
            after ? [ "rustic-init.service" ],
            requires ? [ ],
          }:
          {
            inherit description after;
            environment = rcloneEnv;
            path = rclonePath;
            serviceConfig = {
              Type = "oneshot";
              User = user;
              ExecStart = execStart;
            };
          }
          // lib.optionalAttrs (startAt != null) { inherit startAt; }
          // lib.optionalAttrs (requires != [ ]) { inherit requires; };

        mkRusticJobService =
          args:
          let
            service = mkRusticService args;
          in
          service
          // {
            serviceConfig = service.serviceConfig // maintenanceJobLimits;
          };

        mkBackupService =
          serviceKind: descriptionKind: mkScript: name: backup:
          lib.nameValuePair "rustic-backup-${serviceKind}-${name}" (mkRusticJobService {
            description = "Rustic ${descriptionKind} backup: ${name}";
            user = backup.user;
            execStart = "${mkScript name backup}";
            startAt = backup.startAt;
          });

        postgresAfter = [
          "rustic-init.service"
          "postgresql.service"
        ];
        postgresRequires = [ "postgresql.service" ];

        mkPostgresServices = name: backup: {
          "rustic-backup-postgres-${name}" = mkRusticJobService {
            description = "Rustic PostgreSQL backup: ${name}";
            user = "root";
            execStart = "${mkPostgresBackupScript name backup}";
            startAt = backup.startAt;
            after = postgresAfter;
            requires = postgresRequires;
          };
          "rustic-postgres-globals-${name}" = mkRusticJobService {
            description = "Rustic PostgreSQL globals backup: ${name}";
            user = "root";
            execStart = "${mkPostgresGlobalsScript name backup}";
            after = postgresAfter;
            requires = postgresRequires;
          };
          "rustic-postgres-db-${name}@" = mkRusticJobService {
            description = "Rustic PostgreSQL database backup: ${name} (%i)";
            user = "root";
            execStart = "${mkPostgresDbScript name backup} %i";
            after = postgresAfter;
            requires = postgresRequires;
          };
        };

        mkMaintenanceService =
          name: description: command: settings:
          lib.optionalAttrs settings.enable {
            ${name} = mkRusticJobService {
              inherit description;
              user = "rustic";
              execStart = command settings;
              startAt = settings.startAt;
            };
          };
      in
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
              if echo "$output" | ${pkgs.gnugrep}/bin/grep -q "Config file already exists"; then
                echo "Repository already initialized"
              else
                echo "$output" >&2
                exit 1
              fi
            }
          '';
        };
      }
      // lib.mapAttrs' (mkBackupService "files" "files" mkFilesBackupScript) cfg.backups.files
      // lib.mapAttrs' (mkBackupService "command" "command" mkCommandBackupScript) cfg.backups.commands
      // lib.concatMapAttrs mkPostgresServices cfg.backups.postgres
      // lib.mapAttrs' (mkBackupService "sqlite" "SQLite" mkSqliteBackupScript) cfg.backups.sqlite
      // mkMaintenanceService "rustic-prune" "Rustic prune old backups" (
        settings:
        "${cfg.package}/bin/rustic forget --prune${
          mkRusticArgs {
            inherit (settings) useProfiles extraArgs;
            cacheUser = "rustic";
          }
        }"
      ) cfg.prune
      // mkMaintenanceService "rustic-check" "Rustic repository check" (
        settings:
        "${cfg.package}/bin/rustic check${
          mkRusticArgs {
            inherit (settings) useProfiles extraArgs;
            cacheUser = "rustic";
          }
        }"
      ) cfg.check;

    systemd.slices."rustic-maintenance" = {
      description = "Resource-limited rustic maintenance jobs";
      sliceConfig = {
        CPUWeight = 20;
        IOWeight = 20;
      };
    };
  };
}
