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
            pkgs,
            ...
          }:
          let
            backendEnvironmentFile = "/etc/rustic/opendal.env";
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

            environment.etc."rustic/opendal.env".source =
              config.clan.core.vars.generators.rustic-r2.files."opendal.env".path;
          };
      };
  };
}
