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
    optionalAttrs
    types
    ;

  cfg = config.services.bulwark-webmail;

  secretPathType = types.either types.path types.str;

  kanidmIssuerUrl =
    if cfg.kanidm.origin == null then
      null
    else
      "${lib.removeSuffix "/" cfg.kanidm.origin}/oauth2/openid/${cfg.kanidm.clientId}";

  oauthEnabled = cfg.oauth.enable || cfg.kanidm.enable;
  oauthOnly = cfg.oauth.only || (cfg.kanidm.enable && cfg.kanidm.oauthOnly);
  oauthAutoSso = cfg.oauth.autoSso || (cfg.kanidm.enable && cfg.kanidm.autoSso);
  oauthClientId = if cfg.kanidm.enable then cfg.kanidm.clientId else cfg.oauth.clientId;
  oauthIssuerUrl = if cfg.kanidm.enable then kanidmIssuerUrl else cfg.oauth.issuerUrl;
  oauthClientSecretFile =
    if cfg.kanidm.enable && cfg.kanidm.clientSecretFile != null then
      cfg.kanidm.clientSecretFile
    else
      cfg.oauth.clientSecretFile;

  stateDir = "/var/lib/bulwark-webmail";
  effectivePackage =
    if cfg.basePath == "" then
      cfg.package
    else
      cfg.package.override { nextPublicBasePath = cfg.basePath; };
  locationPath = if cfg.basePath == "" then "/" else cfg.basePath;
in
{
  options.services.bulwark-webmail = {
    enable = mkEnableOption "Bulwark Webmail, a JMAP webmail client for Stalwart Mail Server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../packages/bulwark-webmail { };
      defaultText = lib.literalExpression "pkgs.bulwark-webmail";
      description = "Bulwark Webmail package to run.";
    };

    basePath = mkOption {
      type = types.str;
      default = "";
      example = "/webmail";
      description = ''
        URL base path to bake into the Next.js build. Empty string serves from
        the domain root. Non-empty values must start with / and must not end
        with /.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address for the Bulwark Webmail HTTP listener.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for the Bulwark Webmail HTTP listener.";
    };

    jmapServerUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://mail.example.com";
      description = "Default Stalwart JMAP server URL exposed to Bulwark.";
    };

    sessionSecretFile = mkOption {
      type = types.nullOr secretPathType;
      default = null;
      description = ''
        File containing SESSION_SECRET. When set, systemd passes it through
        LoadCredential and Bulwark enables remember-me cookies and settings sync.
      '';
    };

    settingsSync.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable server-side encrypted settings sync.";
    };

    oauth = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable generic OAuth2 / OIDC login.";
      };

      only = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to hide the username/password login form.";
      };

      autoSso = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to immediately start SSO when OAuth-only login is enabled.";
      };

      clientId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "bulwark-webmail";
        description = "OAuth2 / OIDC client ID.";
      };

      issuerUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://idp.example.com/oauth2/openid/bulwark-webmail";
        description = ''
          OAuth2 / OIDC issuer URL used for discovery. Leave unset to discover
          from jmapServerUrl, which is useful when Stalwart itself is the issuer.
        '';
      };

      clientSecretFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
        description = "File containing the OAuth2 / OIDC client secret for confidential clients.";
      };

      scopes = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "openid email profile groups";
        description = "OAuth scopes to request. Leave unset for Bulwark's default scopes.";
      };
    };

    kanidm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Convenience configuration for Kanidm as the OAuth2 / OIDC issuer.
          Stalwart must still be configured to trust the Kanidm-issued access token.
        '';
      };

      origin = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://idm.example.com";
        description = "Kanidm origin without the /oauth2/openid/<client> suffix.";
      };

      clientId = mkOption {
        type = types.str;
        default = "bulwark-webmail";
        description = "Kanidm OAuth2 resource server / client name.";
      };

      clientSecretFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
        description = "File containing the Kanidm OAuth2 client secret.";
      };

      oauthOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Whether Kanidm login should hide the username/password form.";
      };

      autoSso = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to immediately redirect OAuth-only logins to Kanidm.";
      };
    };

    telemetry.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to allow Bulwark anonymous telemetry.";
    };

    updateCheck.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to allow Bulwark upstream version checks.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        APP_NAME = "Mail";
        ADMIN_PASSWORD = "change-me-on-first-start";
      };
      description = "Additional environment variables for Bulwark Webmail.";
    };

    nginx = {
      enable = mkEnableOption "nginx reverse proxy for Bulwark Webmail";

      hostName = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "webmail.example.com";
        description = "nginx virtual host name.";
      };

      enableACME = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable ACME for the nginx virtual host.";
      };

      forceSSL = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to force HTTPS for the nginx virtual host.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.basePath == "" || (lib.hasPrefix "/" cfg.basePath && !lib.hasSuffix "/" cfg.basePath);
        message = "services.bulwark-webmail.basePath must be empty or start with / and not end with /.";
      }
      {
        assertion = cfg.nginx.enable -> cfg.nginx.hostName != null;
        message = "services.bulwark-webmail.nginx.hostName must be set when nginx proxy is enabled.";
      }
      {
        assertion = cfg.kanidm.enable -> cfg.kanidm.origin != null;
        message = "services.bulwark-webmail.kanidm.origin must be set when Kanidm support is enabled.";
      }
      {
        assertion = cfg.oauth.enable -> cfg.oauth.clientId != null;
        message = "services.bulwark-webmail.oauth.clientId must be set when generic OAuth support is enabled.";
      }
      {
        assertion = oauthOnly -> cfg.sessionSecretFile != null || cfg.environment ? SESSION_SECRET;
        message = "services.bulwark-webmail.sessionSecretFile or environment.SESSION_SECRET is required for OAuth-only SSO.";
      }
    ];

    systemd.services.bulwark-webmail = {
      description = "Bulwark Webmail";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        HOSTNAME = cfg.host;
        PORT = toString cfg.port;
        SETTINGS_DATA_DIR = "${stateDir}/settings";
        ADMIN_DATA_DIR = "${stateDir}/admin";
        TELEMETRY_DATA_DIR = "${stateDir}/telemetry";
        VERSION_CHECK_DATA_DIR = "${stateDir}/version-check";
        SETTINGS_SYNC_ENABLED = if cfg.settingsSync.enable then "true" else "false";
      }
      // optionalAttrs (cfg.jmapServerUrl != null) {
        JMAP_SERVER_URL = cfg.jmapServerUrl;
      }
      // optionalAttrs (cfg.sessionSecretFile != null) {
        SESSION_SECRET_FILE = "%d/session-secret";
      }
      // optionalAttrs oauthEnabled {
        OAUTH_ENABLED = "true";
        OAUTH_ONLY = if oauthOnly then "true" else "false";
        AUTO_SSO_ENABLED = if oauthAutoSso then "true" else "false";
      }
      // optionalAttrs (oauthEnabled && oauthClientId != null) {
        OAUTH_CLIENT_ID = oauthClientId;
      }
      // optionalAttrs (oauthEnabled && oauthIssuerUrl != null) {
        OAUTH_ISSUER_URL = oauthIssuerUrl;
      }
      // optionalAttrs (oauthClientSecretFile != null) {
        OAUTH_CLIENT_SECRET_FILE = "%d/oauth-client-secret";
      }
      // optionalAttrs (cfg.oauth.scopes != null) {
        OAUTH_SCOPES = cfg.oauth.scopes;
      }
      // optionalAttrs (!cfg.telemetry.enable) {
        BULWARK_TELEMETRY = "off";
      }
      // optionalAttrs (!cfg.updateCheck.enable) {
        BULWARK_UPDATE_CHECK = "off";
      }
      // cfg.environment;

      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${stateDir}/settings ${stateDir}/admin ${stateDir}/telemetry ${stateDir}/version-check";
        ExecStart = lib.getExe effectivePackage;
        Restart = "on-failure";
        RestartSec = "5s";

        DynamicUser = true;
        StateDirectory = "bulwark-webmail";
        StateDirectoryMode = "0700";
        LoadCredential =
          optional (cfg.sessionSecretFile != null) "session-secret:${toString cfg.sessionSecretFile}"
          ++ optional (oauthClientSecretFile != null) "oauth-client-secret:${toString oauthClientSecretFile}";

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
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts.${cfg.nginx.hostName} = {
        inherit (cfg.nginx) enableACME forceSSL;
        locations.${locationPath} = {
          proxyPass = "http://${cfg.host}:${toString cfg.port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
