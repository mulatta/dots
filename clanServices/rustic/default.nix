{
  _class = "clan.service";

  manifest = {
    name = "rustic";
    description = "Configure Rustic clients that archive machine state to object storage.";
    categories = [ "System" ];
    readme = builtins.readFile ./README.md;
    constraints = {
      maxInstances = 1;
      roles.client.minMachines = 1;
    };
  };

  roles.client = {
    description = "Archive registered machine state to a host-specific Rustic repository.";

    interface =
      { lib, ... }:
      {
        options = {
          bucket = lib.mkOption {
            type = lib.types.str;
            description = "R2 bucket containing one repository prefix per machine";
          };

          startAt = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 04:00:00";
            description = "Systemd calendar for the machine state backup";
          };

          pruneStartAt = lib.mkOption {
            type = lib.types.str;
            default = "Sun *-*-* 05:00:00";
            description = "Systemd calendar for repository pruning";
          };

          checkStartAt = lib.mkOption {
            type = lib.types.str;
            default = "*-*-01 06:30:00";
            description = "Systemd calendar for repository checks";
          };
        };
      };

    perInstance =
      {
        machine,
        settings,
        ...
      }:
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.services.rustic;
            backendEnvironmentFile = "/etc/rustic/opendal.env";
            systemBackup = cfg.backups.system;
            stateFolders = lib.unique (
              lib.flatten (map (state: state.folders or [ ]) (lib.attrValues config.clan.core.state))
            );
            mkProfileArgs =
              profiles: lib.concatMapStrings (profile: " -P ${lib.escapeShellArg profile}") profiles;
            clanRusticArgs = "${mkProfileArgs systemBackup.useProfiles} --cache-dir ${lib.escapeShellArg "${cfg.cacheBaseDir}/root"}";
            allowedFolderCases = lib.concatMapStringsSep "\n" (
              folder: "${lib.escapeShellArg (toString folder)}) ;;"
            ) stateFolders;

            clanList = pkgs.writeShellApplication {
              name = "rustic-clan-list";
              runtimeInputs = [
                cfg.package
                pkgs.jq
              ];
              text = ''
                set -a
                # shellcheck source=/dev/null
                source ${backendEnvironmentFile}
                set +a
                rustic snapshots --json${clanRusticArgs} \
                  | jq --compact-output '[.[].snapshots[] | {name: .id, job_name: "system"}]'
              '';
            };

            clanCreate = pkgs.writeShellApplication {
              name = "rustic-clan-create";
              runtimeInputs = [ config.systemd.package ];
              text = ''
                systemctl start ${lib.escapeShellArg systemBackup.unitName}.service
              '';
            };

            clanRestore = pkgs.writeShellApplication {
              name = "rustic-clan-restore";
              runtimeInputs = [
                cfg.package
                pkgs.coreutils
              ];
              text = ''
                if [[ -z "''${NAME:-}" ]]; then
                  echo "No Rustic snapshot given via NAME" >&2
                  exit 1
                fi
                if [[ ! "$NAME" =~ ^[0-9a-f]{64}$ ]]; then
                  echo "Invalid Rustic snapshot ID: $NAME" >&2
                  exit 1
                fi
                if [[ -z "''${FOLDERS:-}" ]]; then
                  echo "No state folders given via FOLDERS" >&2
                  exit 1
                fi

                set -a
                # shellcheck source=/dev/null
                source ${backendEnvironmentFile}
                set +a
                IFS=: read -r -a folders <<<"$FOLDERS"
                for folder in "''${folders[@]}"; do
                  case "$folder" in
                    ${allowedFolderCases}
                    *)
                      echo "Refusing to restore unregistered state folder: $folder" >&2
                      exit 1
                      ;;
                  esac
                  mkdir -p "$folder"
                  rustic restore "$NAME:$folder" "$folder"${clanRusticArgs}
                done
              '';
            };
          in
          {
            clan.core = {
              vars.generators = {
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

                rustic-r2 = {
                  share = true;
                  files."opendal.env" = {
                    secret = true;
                    owner = "rustic";
                    group = "rustic";
                  };
                  prompts = {
                    r2_access_key_id = {
                      description = "R2 Access Key ID from Cloudflare Dashboard";
                      type = "line";
                      persist = true;
                    };
                    r2_secret_access_key = {
                      description = "R2 Secret Access Key from Cloudflare Dashboard";
                      type = "hidden";
                      persist = true;
                    };
                    r2_account_id = {
                      description = "Cloudflare Account ID";
                      type = "line";
                      persist = true;
                    };
                  };
                  script = ''
                    write_env() {
                      local name="$1"
                      local value
                      value="$(cat "$2")"
                      if [[ ! "$value" =~ ^[A-Za-z0-9_./+=-]+$ ]]; then
                        echo "Refusing invalid characters in $name" >&2
                        exit 1
                      fi
                      printf '%s=%s\n' "$name" "$value"
                    }

                    account_id="$(cat "$prompts/r2_account_id")"
                    if [[ ! "$account_id" =~ ^[0-9a-fA-F]{32}$ ]]; then
                      echo "Cloudflare Account ID must be 32 hexadecimal characters" >&2
                      exit 1
                    fi

                    {
                      write_env OPENDAL_ACCESS_KEY_ID "$prompts/r2_access_key_id"
                      write_env OPENDAL_SECRET_ACCESS_KEY "$prompts/r2_secret_access_key"
                      printf 'OPENDAL_ENDPOINT=https://%s.r2.cloudflarestorage.com\n' "$account_id"
                    } > "$out/opendal.env"
                  '';
                };
              };

              backups.providers.rustic = {
                list = "rustic-clan-list";
                create = "rustic-clan-create";
                restore = "rustic-clan-restore";
              };
            };

            services.rustic = {
              enable = true;
              environmentFile = backendEnvironmentFile;
              profiles.rustic = {
                repository = {
                  repository = "opendal:s3";
                  password-file = config.clan.core.vars.generators.rustic.files."password.txt".path;
                  options = {
                    bucket = settings.bucket;
                    root = "/${machine.name}";
                    region = "auto";
                    connections = "20";
                  };
                };
                backup.host = machine.name;
              };
              backups.system = {
                startAt = settings.startAt;
                useProfiles = [ "rustic" ];
              };
              prune = {
                enable = true;
                startAt = settings.pruneStartAt;
                useProfiles = [ "rustic" ];
              };
              check = {
                enable = true;
                startAt = settings.checkStartAt;
                useProfiles = [ "rustic" ];
              };
            };

            environment = {
              etc."rustic/opendal.env".source =
                config.clan.core.vars.generators.rustic-r2.files."opendal.env".path;
              systemPackages = [
                clanList
                clanCreate
                clanRestore
              ];
            };
          };
      };
  };
}
