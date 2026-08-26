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
  serverUrl = "http://[${maltWgIP}]:${toString port}";
  authToken = config.clan.core.vars.generators.ai-memory.files.auth-token.path;
  tokenPepper = config.clan.core.vars.generators.ai-memory.files.token-pepper.path;
  configFile = (pkgs.formats.toml { }).generate "ai-memory.toml" {
    bind = "[${maltWgIP}]:${toString port}";
    allowed_hosts = [
      "malt.x"
      "malt"
      maltWgIP
    ];

    # One coding session should remain attached to its starting repository
    # when an agent temporarily visits another checkout or scratch directory.
    routing.mid_session = "sticky";

    # Keep future LLM-generated durable changes reviewable if a provider is
    # enabled later; zero-LLM operation ignores this queue setting.
    auto_improve.require_approval = true;

    auth.root_username = "seungwon";
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
    export AI_MEMORY_AUTH_TOKEN AI_MEMORY_AUTH__TOKEN_PEPPER
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
        "AI_MEMORY_EMBEDDING_PROVIDER=openai-compat"
        "AI_MEMORY_EMBEDDING_BASE_URL=http://psi.n:8201/v1"
        "AI_MEMORY_EMBEDDING_MODEL=Qwen/Qwen3-Embedding-0.6B"
        "AI_MEMORY_EMBEDDING_DIM=1024"
      ];
      LoadCredential = [
        "auth-token:${authToken}"
        "token-pepper:${tokenPepper}"
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

  networking.firewall.interfaces.wireguard.allowedTCPPorts = [ port ];

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
      message = "ai-memory must not expose its bearer-authenticated HTTP port outside WireGuard.";
    }
  ];
}
