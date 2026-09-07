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

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Environment file loaded by every Rustic service";
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
              repository = "opendal:s3";
              options = {
                bucket = "backup";
                root = "/hostname";
              };
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

    backups = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, name, ... }:
          {
            options = commonBackupOptions // {
              unitName = lib.mkOption {
                type = lib.types.str;
                default = "rustic-backup-files-${name}";
                description = "Systemd service and timer base name";
              };

              sources = lib.mkOption {
                type = lib.types.listOf lib.types.path;
                description = "Paths to backup";
              };

              asPath = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Override the backup path in snapshot";
              };

              _resolvedSources = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = map toString config.sources;
                internal = true;
              };

              _resolvedAsPath = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = config.asPath;
                internal = true;
              };

              _commandPrefix = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                internal = true;
              };
            };
          }
        )
      );
      default = { };
      description = "File-based backups";
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
