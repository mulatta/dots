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
  imports = [ ./network.nix ];

  clan.core.vars.generators.hermes = {
    files.slack-bot-token.secret = true;
    files.slack-app-token.secret = true;

    prompts.slack-bot-token.description = "Slack bot token (xoxb-…) for the Nelson app";
    prompts.slack-app-token.description = "Slack app-level token (xapp-…) with connections:write for Nelson";

    script = ''
      cp "$prompts/slack-bot-token" "$out/slack-bot-token"
      cp "$prompts/slack-app-token" "$out/slack-app-token"
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 - - -"
  ];

  containers.hermes = {
    autoStart = true;

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

      users.users.hermes = {
        isSystemUser = true;
        group = "hermes";
        uid = 2001;
        home = stateDir;
      };
      users.groups.hermes.gid = 2001;

      time.timeZone = "Asia/Seoul";
      environment.systemPackages = [ hermesPkg ];

      systemd = {
        tmpfiles.rules =
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

        services = {
          hermes-skill-policy = {
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

          hermes = {
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

          hermes-dashboard = {
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
    };
  };
}
