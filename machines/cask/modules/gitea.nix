{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "git.mulatta.io";
  port = 3002;
in
{
  services.gitea = {
    enable = true;
    database.type = "postgres";
    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        PUBLIC_URL_DETECTION = "never";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = port;
        START_SSH_SERVER = false;
        SSH_DOMAIN = domain;
        SSH_PORT = 22;
        DISABLE_ROUTER_LOG = true;
      };

      service = {
        DISABLE_REGISTRATION = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
        ENABLE_PASSWORD_SIGNIN_FORM = false;
        ENABLE_BASIC_AUTHENTICATION = false;
      };

      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        USERNAME = "preferred_username";
        UPDATE_AVATAR = true;
      };

      security = {
        # Repository administrators cannot upload server-side hooks that would
        # run arbitrary code as the Gitea service user.
        DISABLE_GIT_HOOKS = true;
        DISABLE_QUERY_AUTH_TOKEN = true;
      };

      session = {
        COOKIE_SECURE = true;
        SAME_SITE = "lax";
      };

      repository.DEFAULT_BRANCH = "main";
      actions.ENABLED = false;
      metrics.ENABLED = true;
      log.LEVEL = "Error";
    };
  };

  systemd.services.gitea = {
    serviceConfig = {
      LimitNOFILE = 65536;
      LoadCredential = [
        "oidc-secret:${config.clan.core.vars.generators.kanidm-gitea-oidc.files.gitea-secret.path}"
      ];
    };

    preStart = lib.mkAfter ''
      # The client secret reaches the CLI through the environment, which only the
      # service user and root can read, instead of the world-readable argument
      # list. The assignment is scoped to the invoked binary, never exported.
      gitea_admin() {
        GITEA_ADMIN_OAUTH2_SECRET="$(< "$CREDENTIALS_DIRECTORY/oidc-secret")" \
          ${lib.getExe config.services.gitea.package} \
          --config ${config.services.gitea.customDir}/conf/app.ini \
          admin auth "$@"
      }

      oidc_args=(
        --name kanidm
        --provider openidConnect
        --key gitea
        --auto-discover-url https://idm.mulatta.io/oauth2/openid/gitea/.well-known/openid-configuration
        --scopes openid
        --scopes email
        --scopes profile
        # Kanidm's groups scope includes UUIDs and SPNs. groups_name keeps
        # authorization checks on stable short names such as git_users.
        --scopes groups_name
        --skip-local-2fa
        --required-claim-name groups
        --required-claim-value git_users
        --group-claim-name groups
        --admin-group admins
        --full-name-claim-name name
      )

      id=$(gitea_admin list | ${pkgs.gawk}/bin/awk '$2 == "kanidm" { print $1 }')
      if [[ -n "$id" ]]; then
        gitea_admin update-oauth --id "$id" "''${oidc_args[@]}"
      else
        gitea_admin add-oauth "''${oidc_args[@]}"
      fi
    '';
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "sameorigin";
    extraConfig = ''
      client_max_body_size 512M;
    '';
    locations = {
      "= /metrics".return = "404";
      "= /robots.txt".alias = ./gitea/robots.txt;
      "/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
