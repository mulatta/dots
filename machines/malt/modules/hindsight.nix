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
  version = "0.10.3";
  # Host and container must agree: PostgreSQL peer auth maps this uid to the
  # hindsight role, and the bind-mounted state keeps its owner.
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
  # from Hermes: sudo -u hindsight CODEX_HOME=/var/lib/hindsight/codex codex login
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

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      hindsight-api = {
        image = "ghcr.io/vectorize-io/hindsight-api:${version}@sha256:f80f304db313cbc8775acd601fda7d094f5854ebf9bc252d8134eb9276d56b40";
        user = "${toString hindsightId}:${toString hindsightId}";
        environmentFiles = [ secrets."api.env".path ];
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
          CODEX_HOME = "/data/codex";
          # Bounds retain bursts so a backlog cannot exhaust the subscription quota.
          HINDSIGHT_API_RETAIN_LLM_MAX_CONCURRENT = "4";
          HOME = "/data";
          HF_HOME = "/data/huggingface";
          TZ = "Asia/Seoul";
        };
        volumes = [
          "${stateDir}:/data:rw"
          "/run/postgresql:/run/postgresql:ro"
        ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
      };

      hindsight-cp = {
        image = "ghcr.io/vectorize-io/hindsight-control-plane:${version}@sha256:bf436b78e85b0438afda8d2e4b1fce01b9d12f135a742d1cc276b741766f212d";
        dependsOn = [ "hindsight-api" ];
        environmentFiles = [ secrets."cp.env".path ];
        environment = {
          # start-all.sh derives HOSTNAME and PORT from these and ignores the plain names.
          HINDSIGHT_CP_HOSTNAME = "127.0.0.1";
          HINDSIGHT_CP_PORT = toString cpPort;
          HINDSIGHT_CP_DATAPLANE_API_URL = "http://127.0.0.1:${toString apiPort}";
        };
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
      };
    };
  };

  systemd.services.podman-hindsight-api = {
    requires = [ "postgresql-setup.service" ];
    after = [
      "postgresql-setup.service"
      "systemd-tmpfiles-setup.service"
    ];
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

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ relayPort ];
}
