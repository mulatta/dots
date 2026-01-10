{
  pkgs,
  config,
  ...
}:
let
  domain = "idm.mulatta.io";
  baseDomain = "mulatta.io";
  bindAddress = "127.0.0.1";
  port = 8443;
  stalwartTokenFile = "/var/lib/stalwart-mail/kanidm-token";
in
{
  services.kanidm = {
    enableServer = true;
    enableClient = true;
    package = pkgs.kanidm_1_8;

    # Client settings for CLI tools (used by stalwart token script)
    clientSettings = {
      uri = "https://${domain}";
    };

    serverSettings = {
      inherit domain;
      origin = "https://${domain}";
      bindaddress = "${bindAddress}:${toString port}";

      # LDAP server for IMAP/SMTP authentication (Stalwart, etc.)
      ldapbindaddress = "127.0.0.1:3636";

      # TLS via ACME (nginx handles public TLS, kanidm uses self-signed internally)
      # For direct TLS, use ACME certs:
      tls_chain = "/var/lib/acme/${domain}/fullchain.pem";
      tls_key = "/var/lib/acme/${domain}/key.pem";

      # Trust X-Forwarded-For from nginx
      trust_x_forward_for = true;

      # Online backup
      online_backup = {
        path = "/var/backup/kanidm/";
        schedule = "0 3 * * *"; # Daily at 3 AM
        versions = 7;
      };
    };

    # Declarative user and group provisioning
    provision = {
      enable = true;
      autoRemove = true;

      # Groups
      groups = {
        # Mail users - can access Stalwart Mail
        mail_users = {
          members = [ "seungwon" ];
        };
        # Photo users - can access Immich
        photo_users = {
          members = [ "seungwon" ];
        };
        # Cloud users - can access Nextcloud
        cloud_users = {
          members = [ "seungwon" ];
        };
        # Automation users - can access n8n
        automation_users = {
          members = [ "seungwon" ];
        };
        # Admin group
        admins = {
          members = [ "seungwon" ];
        };
      };

      # Users (persons)
      persons = {
        seungwon = {
          displayName = "Seungwon";
          mailAddresses = [ "seungwon@${baseDomain}" ];
        };
      };

      # OAuth2/OIDC clients
      systems.oauth2 = {
        # Stalwart Mail - public client with PKCE
        stalwart = {
          displayName = "Stalwart Mail";
          originUrl = "https://mail.${baseDomain}";
          originLanding = "https://mail.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.mail_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # Immich - public client with PKCE
        immich = {
          displayName = "Immich Photos";
          originUrl = "https://immich.${baseDomain}";
          originLanding = "https://immich.${baseDomain}";
          public = true;
          enableLocalhostRedirects = true; # For mobile app
          scopeMaps.photo_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # Nextcloud - public client with PKCE
        nextcloud = {
          displayName = "Nextcloud";
          originUrl = [
            "https://nextcloud.${baseDomain}"
            "https://nextcloud.${baseDomain}/apps/user_oidc/code"
          ];
          originLanding = "https://nextcloud.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.cloud_users = [
            "openid"
            "email"
            "profile"
            "groups"
          ];
        };

        # n8n via oauth2-proxy
        n8n = {
          displayName = "n8n Automation";
          originUrl = [
            "https://n8n.${baseDomain}"
            "https://n8n.${baseDomain}/oauth2/callback"
          ];
          originLanding = "https://n8n.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.automation_users = [
            "openid"
            "email"
            "profile"
          ];
        };
      };
    };
  };

  # ACME certificate for Kanidm
  security.acme.certs.${domain} = {
    group = "nginx";
    reloadServices = [
      "kanidm.service"
      "nginx.service"
    ];
  };

  # Ensure backup directory exists
  systemd.tmpfiles.rules = [
    "d /var/backup/kanidm 0750 kanidm kanidm -"
  ];

  # Kanidm needs to read ACME certs
  users.users.kanidm.extraGroups = [ "nginx" ];

  # Wait for ACME certs before starting
  systemd.services.kanidm = {
    after = [
      "acme-${domain}.service"
      "acme-finished-${domain}.target"
    ];
    wants = [ "acme-finished-${domain}.target" ];
  };

  # nginx reverse proxy (optional, for HTTP→HTTPS redirect)
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "https://${bindAddress}:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };

  # Run manually: kanidm login -D idm_admin && systemctl start kanidm-stalwart-token
  systemd.services.kanidm-stalwart-token = {
    description = "Generate Kanidm service account token for Stalwart";
    after = [ "kanidm.service" ];
    requires = [ "kanidm.service" ];
    # Not in wantedBy - must be started manually after idm_admin login
    path = [ config.services.kanidm.package ];
    unitConfig.ConditionPathExists = "!${stalwartTokenFile}";
    script = ''
      set -euo pipefail
      # Verify idm_admin is logged in
      if ! kanidm self whoami --name idm_admin 2>/dev/null; then
        echo "Error: idm_admin not logged in. Run 'kanidm login --name idm_admin' first."
        exit 1
      fi
      kanidm service-account create stalwart_ldap "Stalwart Mail LDAP" idm_admins --name idm_admin || true
      kanidm group add-members idm_people_read stalwart_ldap --name idm_admin || true
      TOKEN=$(kanidm service-account api-token generate stalwart_ldap "ldap-bind" --name idm_admin 2>&1 | tail -1)
      install -m 600 -o stalwart-mail -g stalwart-mail /dev/null "${stalwartTokenFile}"
      echo -n "$TOKEN" > "${stalwartTokenFile}"
      echo "Stalwart LDAP token generated successfully."
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
  };

}
