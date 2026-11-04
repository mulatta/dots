{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.services.agentsview;
  format = pkgs.formats.toml { };

  stateDir = "/var/lib/agentsview";
  credentialsDir = "/run/credentials/agentsview.service";

  managedSettings = pkgs.writeText "agentsview-managed.json" (builtins.toJSON cfg.settings);

  # agentsview writes config.toml itself (cursor_secret, Settings page), so managed keys
  # are merged over the existing file instead of replacing it.
  mergeConfig = pkgs.writeShellApplication {
    name = "agentsview-merge-config";
    runtimeInputs = [
      pkgs.jq
      pkgs.remarshal
    ];
    text = ''
      target=${stateDir}/config.toml
      current='{}'
      if [ -s "$target" ]; then
        current=$(remarshal -f toml -t json "$target")
      fi
      jq --argjson current "$current" '$current * .' ${managedSettings} \
        | remarshal -f json -t toml -o "$target.tmp"
      mv "$target.tmp" "$target"
    '';
  };

  sshConfig = pkgs.writeText "agentsview-ssh-config" (
    cfg.sshConfig
    + lib.optionalString (cfg.sshKeyFile != null) ''

      Host *
        IdentityFile ${credentialsDir}/ssh-key
        IdentitiesOnly yes
    ''
  );
in
{
  options.services.agentsview = {
    enable = mkEnableOption "agentsview, a session archive and web UI for coding agents";

    package = mkOption {
      type = types.package;
      example = lib.literalExpression "inputs.llm-agents.packages.\${system}.agentsview";
      description = "agentsview package to run.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the web UI and API listen on.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port the web UI and API listen on.";
    };

    authTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File holding the bearer token for the API. Setting it enables `require_auth`.
        Required when {option}`services.agentsview.host` is not loopback.
      '';
    };

    settings = mkOption {
      inherit (format) type;
      default = { };
      example = lib.literalExpression ''
        {
          remote_hosts = [
            {
              host = "psi";
              transport = "ssh";
              interval = "15m";
            }
          ];
        }
      '';
      description = ''
        Keys merged into `config.toml` on every start. Keys set here win over Settings
        page edits; other keys, including generated secrets, are kept.
      '';
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Private key used for `transport = "ssh"` remote hosts. It must have no passphrase,
        since the service has no SSH agent.
      '';
    };

    sshConfig = mkOption {
      type = types.lines;
      default = "";
      example = ''
        Host psi
          HostName psi.example.org
          User seungwon
      '';
      description = ''
        OpenSSH client config for the service user. Remote host `destination` values
        resolve against it. Host keys belong in {option}`programs.ssh.knownHosts`, since
        sync runs with `BatchMode=yes` and cannot confirm a new key.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.elem cfg.host [
            "127.0.0.1"
            "::1"
            "localhost"
          ]
          || cfg.authTokenFile != null;
        message = "services.agentsview.authTokenFile is required when host is not loopback.";
      }
    ];

    # Static user: ssh resolves ~/.ssh/config from the passwd home, which DynamicUser sets to /.
    users.users.agentsview = {
      isSystemUser = true;
      group = "agentsview";
      home = stateDir;
    };
    users.groups.agentsview = { };

    systemd.tmpfiles.settings.agentsview = {
      "${stateDir}/.ssh".d = {
        user = "agentsview";
        group = "agentsview";
        mode = "0700";
      };
      "${stateDir}/.ssh/config"."L+".argument = "${sshConfig}";
    };

    systemd.services.agentsview = {
      description = "agentsview";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.openssh ];
      environment = {
        AGENTSVIEW_DATA_DIR = stateDir;
        HOME = stateDir;
        # Deployment variables, including the token file, are read only in this mode.
        AGENTSVIEW_MODE = "serve";
        AGENTSVIEW_NO_BROWSER = "true";
        AGENTSVIEW_DISABLE_UPDATE_CHECK = "1";
      }
      // lib.optionalAttrs (cfg.authTokenFile != null) {
        AGENTSVIEW_REQUIRE_AUTH = "true";
        AGENTSVIEW_AUTH_TOKEN_FILE = "${credentialsDir}/auth-token";
      };
      serviceConfig = {
        ExecStartPre = lib.getExe mergeConfig;
        ExecStart = lib.escapeShellArgs [
          (lib.getExe cfg.package)
          "serve"
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
        ];
        User = "agentsview";
        Group = "agentsview";
        StateDirectory = "agentsview";
        StateDirectoryMode = "0700";
        LoadCredential =
          optional (cfg.authTokenFile != null) "auth-token:${cfg.authTokenFile}"
          ++ optional (cfg.sshKeyFile != null) "ssh-key:${cfg.sshKeyFile}";
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
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };
  };
}
