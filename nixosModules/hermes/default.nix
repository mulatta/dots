# Renders the options into the files Hermes reads and runs the gateway and
# dashboard. The host owns the state directory, credential files and ingress.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hermes;
  hermesHome = "${cfg.stateDir}/.hermes";
  yaml = pkgs.formats.yaml { };
  hindsight = cfg.memory.hindsight;

  # A credential name like `sparkyfitness-api-key` becomes SPARKYFITNESS_API_KEY.
  envName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  optional = cond: attrs: lib.optionalAttrs cond attrs;

  homeOf = name: if name == cfg.defaultProfile then hermesHome else "${hermesHome}/profiles/${name}";

  modelSettings =
    m:
    {
      inherit (m) provider;
      model = m.name;
    }
    // optional (m.reasoningEffort != null) { reasoning_effort = m.reasoningEffort; };

  quietDisplay =
    p:
    optional (!p.progressMessages) {
      interim_assistant_messages = false;
      tool_progress = "off";
    };

  # What each enabled platform adds to a profile: config.yaml values, plain
  # .env values, and .env credentials (variable -> credential name).
  platformParts =
    p:
    let
      inherit (p.platforms) discord;
    in
    lib.optional discord.enable {
      settings = {
        gateway.platforms.discord = {
          home_channel = {
            platform = "discord";
            chat_id = discord.homeChannel;
          };
          gateway_restart_notification = discord.restartNotification;
        };
        display.platforms.discord = quietDisplay discord;
      };
      env = {
        DISCORD_ALLOWED_USERS = lib.concatStringsSep "," discord.allowedUsers;
        DISCORD_REQUIRE_MENTION = lib.boolToString discord.requireMention;
        DISCORD_AUTO_THREAD = lib.boolToString discord.autoThread;
      }
      // optional (discord.freeResponseChannels != [ ]) {
        DISCORD_FREE_RESPONSE_CHANNELS = lib.concatStringsSep "," discord.freeResponseChannels;
      };
      secrets.DISCORD_BOT_TOKEN = discord.botTokenCredential;
    };

  profileSettings =
    name: p:
    lib.foldl' lib.recursiveUpdate { } (
      [
        {
          model = {
            default = p.model.name;
            inherit (p.model) provider;
          };
          auxiliary = lib.mapAttrs (_: modelSettings) p.auxiliary.tasks;
          mcp_servers = lib.mapAttrs (
            _: s:
            {
              inherit (s) url trust;
            }
            // optional (s.auth != null) { inherit (s) auth; }
            // optional (s.bearerTokenCredential != null) {
              headers.Authorization = "Bearer \${${envName s.bearerTokenCredential}}";
            }
          ) p.mcpServers;
        }
        (optional (p.model.reasoningEffort != null) {
          agent.reasoning_effort = p.model.reasoningEffort;
        })
      ]
      ++ map (part: part.settings) (platformParts p)
      ++ [
        (optional (name == cfg.defaultProfile) {
          dashboard = {
            public_url = cfg.dashboard.publicUrl;
            oauth = {
              provider = "self-hosted";
              self_hosted = {
                inherit (cfg.dashboard.oidc) issuer;
                client_id = cfg.dashboard.oidc.clientId;
                scopes = lib.concatStringsSep " " cfg.dashboard.oidc.scopes;
              };
            };
          };
        })
        p.settings
      ]
    );

  profileSecrets =
    p:
    lib.mergeAttrsList (map (part: part.secrets) (platformParts p))
    // p.credentials
    // optional hindsight.enable { HINDSIGHT_API_KEY = hindsight.apiKeyCredential; }
    // lib.listToAttrs (
      map (s: lib.nameValuePair (envName s.bearerTokenCredential) s.bearerTokenCredential) (
        lib.filter (s: s.bearerTokenCredential != null) (lib.attrValues p.mcpServers)
      )
    );

  profileEnv =
    p:
    {
      HERMES_INFERENCE_PROVIDER = p.model.provider;
      HERMES_INFERENCE_MODEL = p.model.name;
      HERMES_MODEL = p.model.name;
    }
    // lib.mergeAttrsList (map (part: part.env) (platformParts p))
    // p.environment;

  managedEnv =
    optional (cfg.browser.cdpUrl != null) { BROWSER_CDP_URL = cfg.browser.cdpUrl; }
    // optional (cfg.search.searxngUrl != null) { SEARXNG_URL = cfg.search.searxngUrl; }
    // optional hindsight.enable (
      let
        python = hindsight.client.pythonModule;
      in
      {
        HINDSIGHT_MODE = "local_external";
        HINDSIGHT_API_URL = hindsight.apiUrl;
        # Hermes' sealed Nix venv appends this read-only tree to sys.path behind its own
        # packages, so the plugin's client imports without shadowing pinned deps.
        HERMES_LAZY_INSTALL_TARGET = "${
          python.withPackages (_: [ hindsight.client ])
        }/${python.sitePackages}";
      }
    )
    // cfg.environment;

  managedSettings = lib.foldl' lib.recursiveUpdate { } [
    { terminal.cwd = "${cfg.stateDir}/workspace"; }
    (optional (cfg.search.searxngUrl != null) { web.search_backend = "searxng"; })
    (optional hindsight.enable {
      memory.provider = "hindsight";
      # A lazy-install target lifts the sealed-venv block; the store path is read-only anyway.
      security.allow_lazy_installs = false;
    })
    cfg.settings
  ];

  toEnvFile = lib.generators.toKeyValue { };

  configFiles = lib.mapAttrs (
    name: p: yaml.generate "hermes-${name}.yaml" (profileSettings name p)
  ) cfg.profiles;

  # Profile secrets stay out of the store: built from $CREDENTIALS_DIRECTORY
  # into tmpfs at start, and each profile's .env links there.
  writeEnvFiles = pkgs.writeShellScript "hermes-env" ''
    set -euo pipefail
    umask 077
    ${lib.concatMapAttrsStringSep "" (name: p: ''
      {
        cat ${pkgs.writeText "hermes-${name}.env" (toEnvFile (profileEnv p))}
        ${lib.concatMapAttrsStringSep "" (env: cred: ''
          # An assignment, unlike a printf argument, fails on a missing credential.
          value=$(< "$CREDENTIALS_DIRECTORY/${cred}")
          printf '%s=%s\n' ${env} "$value"
        '') (profileSecrets p)}
      } > /run/hermes/${name}.env.tmp
      mv /run/hermes/${name}.env.tmp /run/hermes/${name}.env
    '') cfg.profiles}
  '';

  profileCredentials = map (p: lib.attrValues (profileSecrets p)) (lib.attrValues cfg.profiles);
  credentials = lib.unique (lib.concatLists profileCredentials);
  # Hindsight's key is instance-wide and may repeat; everything else names one profile's bot.
  duplicateCredentials = lib.filter (c: lib.count (lib.elem c) profileCredentials > 1) (
    lib.subtractLists (lib.optional hindsight.enable hindsight.apiKeyCredential) credentials
  );

  profileTmpfiles =
    name: _p:
    let
      home = homeOf name;
    in
    # The default profile's home is $HERMES_HOME, created below.
    lib.optional (name != cfg.defaultProfile) "d ${home} 0750 hermes hermes -"
    ++ [
      "d ${home}/skills 0750 hermes hermes -"
      # Preserve curated skills without syncing upstream bundles.
      "f ${home}/.no-bundled-skills 0640 hermes hermes -"
      "d ${home}/plugins 0750 hermes hermes -"
      "L+ ${home}/config.yaml - - - - ${configFiles.${name}}"
      "L+ ${home}/.env - - - - /run/hermes/${name}.env"
    ]
    ++ lib.optional hindsight.enable "L+ ${home}/plugins/hindsight - - - - ${hindsight.plugins}/hermes";

  hardening = {
    User = "hermes";
    Group = "hermes";
    CapabilityBoundingSet = "";
    LockPersonality = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    RestrictSUIDSGID = true;
  };

  agentService = description: args: {
    inherit description;
    wantedBy = [ "multi-user.target" ];
    requires = [ "hermes-env.service" ];
    after = [
      "hermes-env.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    partOf = [ "hermes-env.service" ];
    path = [ "/run/current-system/sw" ];
    # Only process-global values; profile values come from the files above.
    environment = {
      HOME = cfg.stateDir;
      HERMES_HOME = hermesHome;
      TZ = config.time.timeZone;
    };
    serviceConfig = hardening // {
      WorkingDirectory = cfg.stateDir;
      StateDirectory = "hermes";
      StateDirectoryMode = "0750";
      Restart = "on-failure";
      RestartSec = 30;
      ExecStart = "${lib.getExe cfg.package} ${args}";
    };
  };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.profiles ? ${cfg.defaultProfile};
        message = "services.hermes.defaultProfile `${cfg.defaultProfile}` is not a profile.";
      }
      {
        assertion = duplicateCredentials == [ ];
        message = "Hermes credentials used by more than one profile: ${toString duplicateCredentials}. A bot token can serve only one profile.";
      }
      {
        assertion =
          !hindsight.enable || lib.elem hindsight.client.pythonModule cfg.package.nativeBuildInputs;
        message = "hindsight-client must be built with Hermes' Python interpreter.";
      }
    ];

    services.hermes.requiredCredentials = credentials;

    system.build.hermesConfig = pkgs.linkFarm "hermes-config" (
      {
        "etc/hermes/config.yaml" = config.environment.etc."hermes/config.yaml".source;
        "etc/hermes/.env" = config.environment.etc."hermes/.env".source;
      }
      // lib.mapAttrs' (name: lib.nameValuePair "profiles/${name}/config.yaml") configFiles
    );

    # Hermes' managed scope: read by every profile and the launch process.
    environment.etc."hermes/config.yaml".source = yaml.generate "hermes-managed.yaml" managedSettings;
    environment.etc."hermes/.env".text = toEnvFile managedEnv;

    # Hermes runs terminal commands in a login shell, and NixOS' /etc/profile
    # resets PATH there, so tools must live in the system profile rather than
    # only in the units' PATH.
    environment.systemPackages = [
      cfg.package
    ]
    ++ cfg.packages;

    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      inherit (cfg) uid;
      home = cfg.stateDir;
    };
    users.groups.hermes.gid = cfg.uid;

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 hermes hermes -"
      "d ${cfg.stateDir}/workspace 0750 hermes hermes -"
      "d ${hermesHome} 0750 hermes hermes -"
      "d ${hermesHome}/profiles 0750 hermes hermes -"
    ]
    ++ lib.concatLists (lib.mapAttrsToList profileTmpfiles cfg.profiles);

    systemd.services = {
      hermes-env = {
        description = "Hermes per-profile environment files";
        serviceConfig = hardening // {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "hermes";
          RuntimeDirectoryMode = "0700";
          ImportCredential = credentials;
          ExecStart = writeEnvFiles;
        };
      };
      hermes-gateway = agentService "Hermes Agent messaging gateway" "gateway run";
      hermes-dashboard = agentService "Hermes Agent web dashboard" "dashboard --host ${cfg.dashboard.host} --port ${toString cfg.dashboard.port} --no-open --skip-build";
    };
  };
}
