{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiMemory = self.inputs.llm-agents.packages.${system}.ai-memory;
  stateDir = "/var/lib/ai-memory";
  port = 49374;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${self.lib.wgPrefix}:${maltSuffix}";
  tapsWgIP = "${self.lib.wgPrefix}::1";
  serverUrl = "http://[${maltWgIP}]:${toString port}";
  authToken = config.clan.core.vars.generators.ai-memory.files.auth-token.path;
  tokenPepper = config.clan.core.vars.generators.ai-memory.files.token-pepper.path;
  anthropicApiKey = config.clan.core.vars.generators.ai-memory-anthropic.files.api-key.path;
  actorProxyToken = config.clan.core.vars.generators.ai-memory-actor-proxy.files.token.path;
  configFile = (pkgs.formats.toml { }).generate "ai-memory.toml" {
    bind = "[${maltWgIP}]:${toString port}";
    allowed_hosts = [
      "malt.x"
      "malt"
      "memory.mulatta.io"
      "memory-api.mulatta.io"
      maltWgIP
    ];

    # One coding session should remain attached to its starting repository
    # when an agent temporarily visits another checkout or scratch directory.
    routing.mid_session = "sticky";

    # Keep future LLM-generated durable changes reviewable if a provider is
    # enabled later; zero-LLM operation ignores this queue setting.
    auto_improve.require_approval = true;

    auth = {
      root_username = "seungwon";
      secure_cookie = true;
    };
  };
  backupCommand = pkgs.writeShellScript "ai-memory-backup" ''
    set -euo pipefail
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT

    export AI_MEMORY_SERVER_URL=${lib.escapeShellArg serverUrl}
    AI_MEMORY_AUTH_TOKEN=$(< "$CREDENTIALS_DIRECTORY/auth-token")
    export AI_MEMORY_AUTH_TOKEN

    # Rustic expects stdout to contain only archive bytes.
    ${lib.getExe aiMemory} backup --to "$tmp/snapshot.tar.gz" >/dev/null
    ${pkgs.coreutils}/bin/cat "$tmp/snapshot.tar.gz"
  '';
  serverCommand = pkgs.writeShellScript "ai-memory-server" ''
    set -euo pipefail
    AI_MEMORY_AUTH_TOKEN=$(< "$CREDENTIALS_DIRECTORY/auth-token")
    AI_MEMORY_AUTH__TOKEN_PEPPER=$(< "$CREDENTIALS_DIRECTORY/token-pepper")
    AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN=$(< "$CREDENTIALS_DIRECTORY/actor-proxy-token")
    ANTHROPIC_API_KEY=$(< "$CREDENTIALS_DIRECTORY/anthropic-api-key")
    export AI_MEMORY_AUTH_TOKEN AI_MEMORY_AUTH__TOKEN_PEPPER \
      AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN ANTHROPIC_API_KEY
    exec ${lib.getExe aiMemory} \
      --data-dir ${stateDir} \
      --config ${configFile} \
      serve --transport http --enable-web
  '';
in
{
  disko.devices.zpool.zroot.datasets.ai-memory = {
    type = "zfs_fs";
    mountpoint = stateDir;
    options = {
      "com.sun:auto-snapshot" = "true";
      compression = "lz4";
    };
  };

  clan.core.vars.generators.ai-memory = {
    files.auth-token = {
      secret = true;
      owner = "ai-memory";
      group = "ai-memory";
    };
    files.token-pepper = {
      secret = true;
      owner = "ai-memory";
      group = "ai-memory";
    };

    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/auth-token"
      openssl rand -hex 32 > "$out/token-pepper"
    '';
  };

  clan.core.vars.generators.ai-memory-actor-proxy = {
    share = true;
    files.token = {
      secret = true;
      owner = "ai-memory";
      group = "ai-memory";
      restartUnits = [ "ai-memory.service" ];
    };
    # taps includes this generated directive at nginx runtime, keeping the
    # trusted-proxy bearer outside the Nix store.
    files.nginx-config.secret = true;

    runtimeInputs = [ pkgs.openssl ];
    script = ''
      token=$(openssl rand -hex 32)
      printf '%s\n' "$token" > "$out/token"
      printf 'proxy_set_header Authorization "Bearer %s";\n' "$token" > "$out/nginx-config"
    '';
  };

  clan.core.vars.generators.ai-memory-anthropic = {
    prompts.api-key = {
      description = "Anthropic API key for ai-memory consolidation";
      type = "hidden";
      persist = false;
    };
    files.api-key = {
      secret = true;
      owner = "ai-memory";
      group = "ai-memory";
    };

    runtimeInputs = [ pkgs.coreutils ];
    script = ''
      if [ ! -s "$prompts/api-key" ]; then
        echo "Anthropic API key must not be empty" >&2
        exit 1
      fi
      install -m 0600 "$prompts/api-key" "$out/api-key"
    '';
  };

  users.users.ai-memory = {
    isSystemUser = true;
    group = "ai-memory";
    home = stateDir;
  };
  users.groups.ai-memory = { };

  environment.systemPackages = [ aiMemory ];

  systemd.tmpfiles.rules = [
    "Z ${stateDir} 0750 ai-memory ai-memory -"
  ];

  systemd.services.ai-memory = {
    description = "Long-term memory server for coding agents";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ stateDir ];

    serviceConfig = {
      User = "ai-memory";
      Group = "ai-memory";
      WorkingDirectory = stateDir;
      StateDirectory = "ai-memory";
      StateDirectoryMode = "0750";
      UMask = "0077";
      Environment = [
        "AI_MEMORY_LLM_PROVIDER=anthropic"
        "AI_MEMORY_LLM_MODEL=claude-haiku-4-5"
        "AI_MEMORY_EMBEDDING_PROVIDER=openai-compat"
        "AI_MEMORY_EMBEDDING_BASE_URL=http://psi.n:8201/v1"
        "AI_MEMORY_EMBEDDING_MODEL=Qwen/Qwen3-Embedding-0.6B"
        "AI_MEMORY_EMBEDDING_DIM=1024"
      ];
      LoadCredential = [
        "auth-token:${authToken}"
        "token-pepper:${tokenPepper}"
        "actor-proxy-token:${actorProxyToken}"
        "anthropic-api-key:${anthropicApiKey}"
      ];
      ExecStartPre = "${lib.getExe aiMemory} --data-dir ${stateDir} --config ${configFile} init";
      ExecStart = serverCommand;
      Restart = "on-failure";
      RestartSec = 5;

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ stateDir ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictSUIDSGID = true;
    };
  };

  # Proxy identity is trustworthy only when no other peer can bypass taps.
  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname "wireguard" ip6 saddr ${tapsWgIP} tcp dport ${toString port} accept comment "Allow ai-memory only from taps ingress"
  '';

  services.rustic.backups.commands.ai-memory = {
    command = toString backupCommand;
    filename = "/ai-memory/snapshot.tar.gz";
    startAt = "*-*-* 03:00:00";
    useProfiles = [ "rustic" ];
  };

  systemd.services.rustic-backup-command-ai-memory = {
    after = [ "ai-memory.service" ];
    requires = [ "ai-memory.service" ];
    serviceConfig.LoadCredential = "auth-token:${authToken}";
  };

  assertions = [
    {
      assertion = !(lib.elem port config.networking.firewall.allowedTCPPorts);
      message = "ai-memory must not expose its HTTP port globally.";
    }
    {
      assertion = lib.all (interface: !(lib.elem port interface.allowedTCPPorts)) (
        lib.attrValues config.networking.firewall.interfaces
      );
      message = "ai-memory must use a source-restricted taps firewall rule.";
    }
  ];
}
