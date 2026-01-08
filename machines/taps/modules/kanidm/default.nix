{
  pkgs,
  ...
}:
let
  domain = "idm.mulatta.io";
  baseDomain = "mulatta.io";
  bindAddress = "127.0.0.1";
  port = 8443;
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
}
