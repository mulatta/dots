# Hermes runs in a container with its own network namespace; SOUL.md and
# skills stay mutable state in its state directory, outside this public repo.
{
  config,
  lib,
  self,
  pkgs,
  ...
}:
let
  vars = config.clan.core.vars.generators;
  hermes = config.containers.hermes.config.services.hermes;
  aiPkgs = self.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  hostAddress = "10.90.0.1";
  localAddress = "10.90.0.2";
  iface = "ve-hermes";
  credentials = {
    noa-discord-bot-token = vars.hermes-discord.files.bot-token.path;
    noa-sparkyfitness-api-key = vars.hermes-sparkyfitness.files.api-key.path;
    hindsight-api-key = vars.hindsight.files.api-key.path;
    noa-youtube-mcp-token = vars.youtube-mcp.files.token.path;
  };
  loopbackServices = {
    hindsight-api = 8890;
    searxng = 8888;
    neko-cdp = 9222;
    youtube-mcp = config.services.flakelets.services.youtube-mcp.settings.port;
  };
  url = port: "http://${hostAddress}:${toString port}";
in
{
  imports = [
    ./platforms.nix
    ./mcp.nix
    ./dashboard.nix
    ./auxiliary.nix
  ];

  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    inherit (hermes) uid;
    home = hermes.stateDir;
  };
  users.groups.hermes.gid = hermes.uid;
  systemd.tmpfiles.rules = [ "d ${hermes.stateDir} 0750 hermes hermes -" ];

  containers.hermes = {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;
    bindMounts.${hermes.stateDir} = {
      hostPath = hermes.stateDir;
      isReadOnly = false;
    };
    # A credential the container needs but the host lacks fails evaluation here.
    extraFlags = map (
      name: "--load-credential=${name}:${credentials.${name}}"
    ) hermes.requiredCredentials;

    config = {
      imports = [
        ../agent-container.nix
        ../../../../nixosModules/hermes
      ];

      system.stateVersion = "25.05";
      time.timeZone = "Asia/Seoul";
      networking.nameservers = [ hostAddress ];
      # The host resolv.conf points at its own stub, unreachable from this namespace.
      networking.useHostResolvConf = false;

      services.hermes = {
        enable = true;
        # Hermes keeps its own ChatGPT login in its state directory. Log in from
        # `sudo nixos-container root-login hermes` via
        # `runuser -u hermes -- env HOME=/var/lib/hermes hermes auth add openai-codex`;
        # runuser keeps root's HOME, and -l fails on the nologin shell.
        package = aiPkgs.hermes-agent;
        defaultProfile = "noa";

        settings = {
          # Codex CLI and Claude Code refresh their own logins with single-use
          # refresh tokens; if Hermes borrowed them, each would log the other out.
          auth.adopt_external_logins = false;
          onboarding.profile_build = "off";
        };

        profiles.noa = {
          model = {
            provider = "openai-codex";
            name = "gpt-6.1-sol";
            reasoningEffort = "low";
          };
          environment.HERMES_MEDIA_ALLOW_DIRS = "${hermes.stateDir}/workspace";
          settings = {
            model.openai_runtime = "auto";
            compression = {
              codex_gpt55_autoraise = true;
              codex_gpt55_autoraise_notice = false;
            };
          };
        };

        memory.hindsight = {
          enable = true;
          apiUrl = url loopbackServices.hindsight-api;
          client = selfPkgs.hindsight-client;
          plugins = selfPkgs.hindsight-plugins;
        };
        # Hermes' browser tools shell out to agent-browser, which attaches to Neko.
        packages = [ aiPkgs.agent-browser ];
        browser.cdpUrl = url loopbackServices.neko-cdp;
        search.searxngUrl = url loopbackServices.searxng;
      };
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ iface ];
    externalInterface = "enp10s0";
  };
  networking.firewall.interfaces.${iface} = {
    allowedTCPPorts = [
      53
    ]
    ++ lib.attrValues loopbackServices;
    allowedUDPPorts = [ 53 ];
  };
  services.resolved.settings.Resolve.DNSStubListenerExtra = hostAddress;
  # The NixOS firewall does not filter forwarded traffic.
  networking.nftables.tables.hermes-isolation = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -5; policy accept;
        iifname "${iface}" ct state established,related accept
        iifname "${iface}" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } drop
        iifname "${iface}" ip6 daddr { ::1/128, fc00::/7, fe80::/10 } drop
      }
    '';
  };
  systemd.sockets = lib.mapAttrs' (
    name: port:
    lib.nameValuePair "hermes-proxy-${name}" {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${hostAddress}:${toString port}" ];
      socketConfig.FreeBind = true;
    }
  ) loopbackServices;
  systemd.services = lib.mapAttrs' (
    name: port:
    lib.nameValuePair "hermes-proxy-${name}" {
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString port}";
        DynamicUser = true;
        PrivateTmp = true;
      };
    }
  ) loopbackServices;

  # FODs run in the host namespace and would bypass the container's isolation.
  nix.firewall = {
    enable = true;
    allowPrivateNetworks = false;
    extraNftablesRules = [
      # resolved.nix only opens UDP.
      "ip daddr { 127.0.0.53, 127.0.0.54 } tcp dport 53 accept"
      # Missing from nixpkgs' private ranges.
      "ip daddr 100.64.0.0/10 counter drop"
      "ip6 daddr fc00::/7 counter drop"
    ];
  };
  networking.nftables.flushRuleset = false;
}
