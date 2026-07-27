{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = self.inputs.llm-agents.packages.${system};
  hermesPkg = aiPkgs.hermes-agent;
  stateDir = "/var/lib/hermes";
  agentBridge = "br-agents";
  hostAddress = "10.233.0.1";
  localAddress = "10.233.0.10";
  gen = config.clan.core.vars.generators.hermes;
  runtimePath = [
    hermesPkg
  ]
  ++ (with pkgs; [
    bash
    coreutils
    curl
    fd
    file
    findutils
    git
    gnugrep
    gnused
    gnutar
    gzip
    jq
    openssh
    procps
    ripgrep
    unzip
    util-linux
    which
    xz
  ]);
  runtimeEnv = {
    TZ = "Asia/Seoul";
    HOME = stateDir;
    HERMES_HOME = "${stateDir}/.hermes";
    HERMES_INFERENCE_PROVIDER = "openai-codex";
    HERMES_INFERENCE_MODEL = "gpt-5.5";
    SLACK_ALLOWED_USERS = "U04GMC10NNP";
  };
in
{
  clan.core.vars.generators.hermes = {
    files.slack-bot-token.secret = true;
    files.slack-app-token.secret = true;

    prompts.slack-bot-token.description = "Slack bot token (xoxb-…) for the Hermes app";
    prompts.slack-app-token.description = "Slack app-level token (xapp-…) with connections:write";

    script = ''
      cp "$prompts/slack-bot-token" "$out/slack-bot-token"
      cp "$prompts/slack-app-token" "$out/slack-app-token"
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 - - -"
  ];

  networking = {
    bridges.${agentBridge}.interfaces = [ ];
    interfaces.${agentBridge}.ipv4.addresses = [
      {
        address = hostAddress;
        prefixLength = 24;
      }
    ];

    nat = {
      enable = true;
      externalInterface = "enp1s0";
      internalInterfaces = [ agentBridge ];
    };

    firewall.filterForward = true;
    nftables.tables.hermes-isolation = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -5; policy accept;
          iifname "${agentBridge}" ct state established,related accept
          iifname "${agentBridge}" drop
        }

        chain forward {
          type filter hook forward priority -5; policy accept;
          iifname "${agentBridge}" ct state established,related accept
          iifname "${agentBridge}" oifname "enp1s0" tcp dport 443 accept
          iifname "${agentBridge}" oifname "enp1s0" udp dport 53 accept
          iifname "${agentBridge}" oifname "enp1s0" tcp dport 53 accept
          iifname "${agentBridge}" drop
        }
      '';
    };
  };

  containers.hermes = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = agentBridge;
    localAddress = "${localAddress}/24";

    bindMounts.${stateDir} = {
      hostPath = stateDir;
      isReadOnly = false;
    };

    extraFlags = [
      "--load-credential=slack-bot-token:${gen.files.slack-bot-token.path}"
      "--load-credential=slack-app-token:${gen.files.slack-app-token.path}"
    ];

    config = _: {
      system.stateVersion = "25.05";

      networking = {
        useHostResolvConf = false;
        nftables.enable = true;
        defaultGateway = {
          address = hostAddress;
          interface = "eth0";
        };
        nameservers = [
          "117.16.191.6"
          "168.126.63.1"
        ];
        firewall.extraInputRules = ''
          ip saddr ${hostAddress} tcp dport 9119 accept
        '';
      };

      users.users.hermes = {
        isSystemUser = true;
        group = "hermes";
        uid = 2001;
        home = stateDir;
      };
      users.groups.hermes.gid = 2001;

      environment.etc."timezone".text = "Asia/Seoul\n";
      environment.systemPackages = [ hermesPkg ];

      systemd.tmpfiles.rules =
        let
          hermesConfig = pkgs.writers.writeYAML "hermes-config.yaml" { };
        in
        [
          "d ${stateDir} 0750 hermes hermes -"
          "d ${stateDir}/.hermes 0750 hermes hermes -"
          "d ${stateDir}/.hermes/skills 0750 hermes hermes -"
          "f ${stateDir}/.hermes/skills/.no-bundled-skills 0640 hermes hermes -"
          "L+ ${stateDir}/.hermes/config.yaml - - - - ${hermesConfig}"
        ];

      systemd.services.hermes-skill-policy = {
        description = "Apply Nelson's declarative skill policy";
        wantedBy = [ "multi-user.target" ];
        before = [
          "hermes.service"
          "hermes-dashboard.service"
        ];

        path = runtimePath;
        environment = runtimeEnv;

        serviceConfig = {
          Type = "oneshot";
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = stateDir;
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "hermes-skill-policy" ''
            set -euo pipefail
            exec ${lib.getExe hermesPkg} skills opt-out --remove --yes
          '';
        };
      };

      systemd.services.hermes = {
        description = "Hermes Agent Slack gateway";
        wantedBy = [ "multi-user.target" ];
        after = [
          "hermes-skill-policy.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "hermes-skill-policy.service" ];

        path = runtimePath;
        environment = runtimeEnv;

        serviceConfig = {
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = stateDir;
          StateDirectory = "hermes";
          ImportCredential = [
            "slack-bot-token"
            "slack-app-token"
          ];
          Restart = "on-failure";
          RestartSec = 30;
          ExecStart = pkgs.writeShellScript "hermes-gateway" ''
            set -euo pipefail
            SLACK_BOT_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-bot-token")
            SLACK_APP_TOKEN=$(< "$CREDENTIALS_DIRECTORY/slack-app-token")
            export SLACK_BOT_TOKEN SLACK_APP_TOKEN
            exec ${lib.getExe hermesPkg} gateway run
          '';
        };
      };

      systemd.sockets.hermes-dashboard-proxy = {
        description = "Private bridge socket for the Hermes dashboard";
        wantedBy = [ "sockets.target" ];
        socketConfig.ListenStream = "${localAddress}:9119";
      };

      systemd.services.hermes-dashboard-proxy = {
        description = "Proxy the private bridge to the loopback-only Hermes dashboard";
        after = [ "hermes-dashboard.service" ];
        requires = [ "hermes-dashboard.service" ];
        serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:9119";
      };

      systemd.services.hermes-dashboard = {
        description = "Hermes Agent web dashboard";
        wantedBy = [ "multi-user.target" ];
        after = [
          "hermes-skill-policy.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "hermes-skill-policy.service" ];

        path = runtimePath;
        environment = runtimeEnv;

        serviceConfig = {
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = stateDir;
          StateDirectory = "hermes";
          Restart = "on-failure";
          RestartSec = 30;
          ExecStart = pkgs.writeShellScript "hermes-dashboard" ''
            set -euo pipefail
            exec ${lib.getExe hermesPkg} dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build
          '';
        };
      };
    };
  };
}
