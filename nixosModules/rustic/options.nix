{
  lib,
  pkgs,
  ...
}:

let
  tomlFormat = pkgs.formats.toml { };

  scheduleOptions = {
    startAt = lib.mkOption {
      type = with lib.types; either (listOf str) str;
      description = "Time(s) at which to run this backup. Format: man systemd.time";
    };
  };

  rusticCommandOptions = {
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
  };

  backupUserOptions = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run the backup as (root recommended for file access)";
    };
  };

  commonBackupOptions = scheduleOptions // rusticCommandOptions // backupUserOptions;

  postgresBackupOptions = scheduleOptions // rusticCommandOptions;
in
{
  options.services.rustic = {
    enable = lib.mkEnableOption "rustic backup service";

    package = lib.mkPackageOption pkgs "rustic" { };

    cacheBaseDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/rustic";
      description = ''
        Base directory for per-service-user rustic caches.

        Rustic caches include repository indexes. Sharing one cache between root
        backup jobs and unprivileged prune/check jobs leaves root-owned stale
        index files behind, which can make checks report remote 404s for packs
        that pruning already removed.
      '';
    };

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
            options = postgresBackupOptions // {
              prefix = lib.mkOption {
                type = lib.types.str;
                default = "/postgres";
                description = "Path prefix for dumps in the backup";
              };
              excludeDatabases = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "stalwart-mail" ];
                description = "Databases to skip (e.g. backed up another way).";
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
}
