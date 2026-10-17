{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  pg = config.services.postgresql;
  cask = self.nixosConfigurations.cask.config.networking.naru;
  stateDir = "/var/lib/hindsight";
  # Fixed so the existing state keeps its owner; peer auth maps the user to the hindsight role.
  hindsightId = 2002;
  apiPort = 8890;
  cpPort = 9999;
  relayPort = 9121;
  secrets = config.clan.core.vars.generators.hindsight.files;

  extensions = [
    "vector"
    "pgroonga"
  ];
  # Neither extension is trusted, so the hindsight role cannot create them itself.
  # ALTER EXTENSION UPDATE keeps the catalog in step with package bumps (pgroonga requires it).
  setupSql = pkgs.writeText "hindsight-pg-setup.sql" ''
    ${lib.concatMapStringsSep "\n" (ext: ''CREATE EXTENSION IF NOT EXISTS "${ext}";'') extensions}
    ${lib.concatMapStringsSep "\n" (ext: ''ALTER EXTENSION "${ext}" UPDATE;'') extensions}
  '';
in
{
  # pgroonga's TokenBigram covers Korean without a dictionary.
  services.postgresql = {
    extensions = ps: [
      ps.pgvector
      ps.pgroonga
    ];
    ensureDatabases = [ "hindsight" ];
    ensureUsers = [
      {
        name = "hindsight";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
    "${lib.getExe' pg.package "psql"} -d hindsight -v ON_ERROR_STOP=1 -f ${setupSql}"
  ];

  users.users.hindsight = {
    isSystemUser = true;
    group = "hindsight";
    uid = hindsightId;
    home = stateDir;
  };
  users.groups.hindsight.gid = hindsightId;

  # Codex refresh tokens rotate on use, so Hindsight keeps its own login apart
  # from Hermes. sudo's secure_path hides the user's codex, hence the full path:
  # sudo -u hindsight CODEX_HOME=/var/lib/hindsight/codex "$(which codex)" login --device-auth
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 hindsight hindsight -"
    "d ${stateDir}/codex 0700 hindsight hindsight -"
    "d ${stateDir}/huggingface 0750 hindsight hindsight -"
  ];

  clan.core.vars.generators.hindsight = {
    files.api-key.secret = true;
    files."api.env".secret = true;
    files."cp.env".secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      key=$(openssl rand -hex 32)
      printf '%s' "$key" > "$out/api-key"
      printf 'HINDSIGHT_API_TENANT_API_KEY=%s\n' "$key" > "$out/api.env"
      printf 'HINDSIGHT_CP_DATAPLANE_API_KEY=%s\n' "$key" > "$out/cp.env"
    '';
  };

  systemd.services.hindsight-api = {
    description = "Hindsight memory API";
    wantedBy = [ "multi-user.target" ];
    requires = [ "postgresql-setup.service" ];
    after = [
      "postgresql-setup.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    environment = {
      HINDSIGHT_API_HOST = "127.0.0.1";
      HINDSIGHT_API_PORT = toString apiPort;
      HINDSIGHT_API_DATABASE_URL = "postgresql://hindsight@/hindsight?host=/run/postgresql";
      HINDSIGHT_API_TENANT_EXTENSION = "hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension";
      HINDSIGHT_API_TEXT_SEARCH_EXTENSION = "pgroonga";
      # The bundled English-only defaults bury Korean candidates (#5172);
      # KURE-v1 scored MRR 0.79 against 0.16 for an English model in cocobee.
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "local";
      HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL = "nlpai-lab/KURE-v1";
      HINDSIGHT_API_RERANKER_PROVIDER = "local";
      HINDSIGHT_API_RERANKER_LOCAL_MODEL = "BAAI/bge-reranker-v2-m3";
      # The default 300 pairs take minutes on CPU, and larger pools cost accuracy.
      HINDSIGHT_API_RERANKER_MAX_CANDIDATES = "50";
      # Low-effort Luna leads the retain leaderboard and bills to the ChatGPT plan.
      HINDSIGHT_API_LLM_PROVIDER = "openai-codex";
      HINDSIGHT_API_LLM_MODEL = "gpt-6-luna";
      HINDSIGHT_API_LLM_REASONING_EFFORT = "low";
      # Low-effort Luna ignores the keep-the-input-language rule and drifts into Hindi.
      HINDSIGHT_API_LLM_OUTPUT_LANGUAGE = "Korean";
      # Replaces the per-call random prompt_cache_key; the overlay's patch mirrors it
      # into the headers the Codex backend actually caches on.
      HINDSIGHT_API_LLM_EXTRA_BODY = builtins.toJSON { prompt_cache_key = "hindsight"; };
      CODEX_HOME = "${stateDir}/codex";
      # Bounds retain bursts so a backlog cannot exhaust the subscription quota.
      HINDSIGHT_API_RETAIN_LLM_MAX_CONCURRENT = "4";
      HOME = stateDir;
      HF_HOME = "${stateDir}/huggingface";
    };
    serviceConfig = {
      ExecStart = lib.getExe' pkgs.hindsight "hindsight-api";
      EnvironmentFile = secrets."api.env".path;
      User = "hindsight";
      Group = "hindsight";
      WorkingDirectory = stateDir;
      NoNewPrivileges = true;
      Restart = "on-failure";
    };
  };

  systemd.services.hindsight-cp = {
    description = "Hindsight control plane";
    wantedBy = [ "multi-user.target" ];
    requires = [ "hindsight-api.service" ];
    after = [ "hindsight-api.service" ];
    environment = {
      HOSTNAME = "127.0.0.1";
      PORT = toString cpPort;
      HINDSIGHT_CP_DATAPLANE_API_URL = "http://127.0.0.1:${toString apiPort}";
    };
    serviceConfig = {
      ExecStart =
        lib.getExe
          self.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hindsight-control-plane;
      EnvironmentFile = secrets."cp.env".path;
      DynamicUser = true;
      NoNewPrivileges = true;
      Restart = "on-failure";
    };
  };

  # The control plane has no OIDC; cask fronts it with oauth2-proxy and is the
  # only peer allowed through this Naru relay.
  services.nginx.enable = true;
  services.nginx.virtualHosts."hindsight.mulatta.io" = {
    listen = [
      {
        addr = config.networking.naru.ipv4;
        port = relayPort;
      }
      {
        addr = "[${config.networking.naru.ipv6}]";
        port = relayPort;
      }
    ];
    extraConfig = ''
      allow ${cask.ipv4};
      allow ${cask.ipv6};
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString cpPort}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Forwarded-Proto https;
        client_max_body_size 100M;
      '';
    };
  };

  networking.firewall.extraInputRules = ''
    iifname "tinc.naru" ip saddr ${cask.ipv4} tcp dport ${toString relayPort} accept
    iifname "tinc.naru" ip6 saddr ${cask.ipv6} tcp dport ${toString relayPort} accept
  '';
}
