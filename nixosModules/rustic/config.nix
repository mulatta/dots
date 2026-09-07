{
  config,
  lib,
  pkgs,
  ...
}:

let
  tomlFormat = pkgs.formats.toml { };
  cfg = config.services.rustic;

  # Default retention policy applied to all profiles
  defaultProfileSettings = {
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
      sourcesArgs = lib.concatMapStrings (s: " ${lib.escapeShellArg s}") backup._resolvedSources;
      asPathArg = lib.optionalString (
        backup._resolvedAsPath != null
      ) " --as-path ${lib.escapeShellArg backup._resolvedAsPath}";
      rusticArgs = mkRusticArgs {
        inherit (backup) useProfiles extraArgs;
        cacheUser = backup.user;
      };
    in
    pkgs.writeScript "rustic-backup-files-${name}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${cfg.package}/bin/rustic backup --init${sourcesArgs}${asPathArg}${rusticArgs}
    '';

  backupUsers = lib.unique (
    [
      "root"
      "rustic"
    ]
    ++ lib.mapAttrsToList (_: backup: backup.user) cfg.backups
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

    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [
      "d ${cfg.cacheBaseDir} 0755 root root - -"
    ]
    ++ map cacheDirRuleFor backupUsers;

    environment.etc = lib.mapAttrs' (k: v: {
      name = "rustic/${k}.toml";
      value.source = v;
    }) configFiles;

    systemd.services =
      let
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
            serviceConfig = {
              Type = "oneshot";
              User = user;
              ExecStart = execStart;
            }
            // lib.optionalAttrs (cfg.environmentFile != null) {
              EnvironmentFile = cfg.environmentFile;
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

        mkFilesBackupService =
          name: backup:
          let
            backupScript = mkFilesBackupScript name backup;
          in
          lib.nameValuePair backup.unitName (mkRusticJobService {
            description = "Rustic files backup: ${name}";
            user = backup.user;
            execStart = lib.escapeShellArgs (backup._commandPrefix ++ [ "${backupScript}" ]);
            startAt = backup.startAt;
          });

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
          restartTriggers = builtins.attrValues configFiles;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "rustic";
          }
          // lib.optionalAttrs (cfg.environmentFile != null) {
            EnvironmentFile = cfg.environmentFile;
          };
          script = ''
            probe_repository() {
              probe_output="$(${cfg.package}/bin/rustic snapshots 2>&1)"
            }

            if probe_repository; then
              echo "Repository already initialized"
            elif ${pkgs.gnugrep}/bin/grep -Fq "No repository config file found for" <<<"$probe_output"; then
              ${cfg.package}/bin/rustic init
              echo "Repository initialized successfully"
            else
              deadline=$((SECONDS + 30))
              while (( SECONDS < deadline )); do
                ${pkgs.coreutils}/bin/sleep 2
                if probe_repository; then
                  echo "Repository became available"
                  exit 0
                fi
              done
              printf '%s\n' "$probe_output" >&2
              exit 1
            fi
          '';
        };
      }
      // lib.mapAttrs' mkFilesBackupService cfg.backups
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
