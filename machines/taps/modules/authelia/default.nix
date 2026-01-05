{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  baseDomain = "mulatta.io";
  ldapBaseDn = "dc=mulatta,dc=io";
  autheliaPort = 9091;

  # Read OAuth client secret hashes from malt (public values)
  immichClientSecretHash = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "immich-oauth";
    file = "client-secret-hash";
  };

  nextcloudClientSecretHash = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "nextcloud-oauth";
    file = "client-secret-hash";
  };
in
{

  clan.core.vars.generators.authelia-oidc-jwks = {
    files."jwks.pem" = {
      secret = true;
      owner = "authelia-main";
    };
    runtimeInputs = with pkgs; [ openssl ];
    script = ''
      openssl genrsa -out "$out/jwks.pem" 4096
    '';
  };

  clan.core.vars.generators.authelia-secrets = {
    files."jwt-secret" = {
      secret = true;
      owner = "authelia-main";
    };
    files."session-secret" = {
      secret = true;
      owner = "authelia-main";
    };
    files."storage-encryption-key" = {
      secret = true;
      owner = "authelia-main";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 48 | tr -d '\n' > "$out/jwt-secret"
      openssl rand -base64 48 | tr -d '\n' > "$out/session-secret"
      openssl rand -base64 48 | tr -d '\n' > "$out/storage-encryption-key"
    '';
  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.clan.core.vars.generators.authelia-secrets.files."jwt-secret".path;
      storageEncryptionKeyFile =
        config.clan.core.vars.generators.authelia-secrets.files."storage-encryption-key".path;
      sessionSecretFile = config.clan.core.vars.generators.authelia-secrets.files."session-secret".path;
      oidcIssuerPrivateKeyFile =
        config.clan.core.vars.generators.authelia-oidc-jwks.files."jwks.pem".path;
    };

    # LDAP bind password - use LLDAP admin account (auto-created on first start)
    environmentVariables = {
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
        config.clan.core.vars.generators.lldap-secrets.files."admin-password".path;
    };

    settings = {
      theme = "auto";
      default_2fa_method = "totp";

      server.address = "tcp://127.0.0.1:${toString autheliaPort}";

      log = {
        level = "info";
        format = "text";
      };

      authentication_backend = {
        password_reset.disable = false;
        ldap = {
          implementation = "lldap";
          address = "ldap://127.0.0.1:3890";
          base_dn = ldapBaseDn;
          user = "uid=admin,ou=people,${ldapBaseDn}";

          users_filter = "(&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))";
          groups_filter = "(member={dn})";

          attributes = {
            username = "uid";
            display_name = "displayName";
            mail = "mail";
            group_name = "cn";
          };
        };
      };

      session = {
        name = "authelia_session";
        same_site = "lax";
        expiration = "1h";
        inactivity = "5m";
        remember_me = "1M";
        cookies = [
          {
            domain = baseDomain;
            authelia_url = "https://auth.${baseDomain}";
            default_redirection_url = "https://${baseDomain}";
          }
        ];
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      notifier = {
        disable_startup_check = true;
        smtp = {
          address = "submission://mail.${baseDomain}:587";
          sender = "Authelia <authelia@${baseDomain}>";
          tls = {
            server_name = "mail.${baseDomain}";
            skip_verify = true;
          };
        };
      };

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = "auth.${baseDomain}";
            policy = "bypass";
          }
          {
            domain = "*.${baseDomain}";
            policy = "one_factor";
          }
        ];
      };

      # OIDC Identity Provider
      identity_providers.oidc = {
        clients = [
          {
            client_id = "immich";
            client_name = "Immich";
            client_secret = immichClientSecretHash;
            public = false;
            authorization_policy = "one_factor";
            redirect_uris = [
              "https://immich.${baseDomain}/auth/login"
              "https://immich.${baseDomain}/user-settings"
              "app.immich:///oauth-callback"
            ];
            scopes = [
              "openid"
              "email"
              "profile"
            ];
            token_endpoint_auth_method = "client_secret_post";
          }
          {
            client_id = "nextcloud";
            client_name = "Nextcloud";
            client_secret = nextcloudClientSecretHash;
            public = false;
            authorization_policy = "one_factor";
            redirect_uris = [
              "https://nextcloud.${baseDomain}/apps/user_oidc/code"
            ];
            scopes = [
              "openid"
              "email"
              "profile"
              "groups"
            ];
            token_endpoint_auth_method = "client_secret_post";
          }
        ];
      };
    };
  };

  systemd.services.authelia-main = {
    after = [ "lldap.service" ];
    requires = [ "lldap.service" ];
  };

  services.nginx.virtualHosts."auth.${baseDomain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString autheliaPort}";
      proxyWebsockets = true;
    };
  };
}
