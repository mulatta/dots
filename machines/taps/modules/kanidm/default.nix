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

  # OAuth2 client logos (pinned to package versions)
  icons = {
    # Nextcloud 32.0.3 - pinned to nextcloud.com repo commit
    nextcloud = pkgs.fetchurl {
      name = "nextcloud.svg";
      url = "https://raw.githubusercontent.com/nextcloud/nextcloud.com/35505202100647f0363b3e12efd66a19bf060d6f/assets/img/logo/logo_nextcloud_blue.svg";
      hash = "sha256-vKr7ILKaS1emP3/TcoctglXugvFP+hEQthXS4cGRXzY=";
    };
    # Immich 2.4.1
    immich = pkgs.fetchurl {
      name = "immich.svg";
      url = "https://raw.githubusercontent.com/immich-app/immich/v2.4.1/design/immich-logo.svg";
      hash = "sha256-36XvcE0HhUkUMGwMIkFzvaJxD4/A3/6314aQ9Y+YEaY=";
    };
    # Stalwart 0.14.1
    stalwart = pkgs.fetchurl {
      name = "stalwart.svg";
      url = "https://raw.githubusercontent.com/stalwartlabs/mail-server/v0.14.1/img/logo-red.svg";
      hash = "sha256-SUwYWRjKZPaB8QcIFtc2c0YJEVIsZsCPXAuhgx8bUPA=";
    };
    # n8n 1.120.4 - from simple-icons repo (pinned commit)
    n8n = pkgs.fetchurl {
      name = "n8n.svg";
      url = "https://raw.githubusercontent.com/simple-icons/simple-icons/faa4f93283a90f0196f3d320968bd38972a27894/icons/n8n.svg";
      hash = "sha256-9aYGGIx4vxNP59ha49ExD29Le+r80dL73vKvAskiQKg=";
    };
    # Linkwarden 2.8.0 - from official repo
    linkwarden = pkgs.fetchurl {
      name = "linkwarden.png";
      url = "https://raw.githubusercontent.com/linkwarden/linkwarden/v2.8.0/assets/logo.png";
      hash = "sha256-4lcQ7oRkBMAT8OYLzETxpSaFjBTUeo7V3XfZFDPdARQ=";
    };
  };
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

      # Trust X-Forwarded-For from nginx reverse proxy
      http_client_address_info = {
        x-forward-for = [ "127.0.0.1" ];
      };

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
        # Bookmark users - can access Linkwarden
        bookmark_users = {
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
          imageFile = icons.stalwart;
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
          imageFile = icons.immich;
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
          imageFile = icons.nextcloud;
          originUrl = [
            "https://cloud.${baseDomain}"
            "https://cloud.${baseDomain}/apps/user_oidc/code"
          ];
          originLanding = "https://cloud.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          # Use short username (seungwon) instead of SPN (seungwon@idm.mulatta.io)
          # Required for vdirsyncer CalDAV/CardDAV URL compatibility
          preferShortUsername = true;
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
          imageFile = icons.n8n;
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

        # Linkwarden - bookmark manager (confidential client)
        linkwarden = {
          displayName = "Linkwarden";
          imageFile = icons.linkwarden;
          originUrl = [
            "https://links.${baseDomain}"
            "https://links.${baseDomain}/api/v1/auth/callback/authentik"
          ];
          originLanding = "https://links.${baseDomain}";
          # Confidential client - requires client_secret
          # Generate secret: kanidm system oauth2 show-basic-secret linkwarden
          public = false;
          enableLocalhostRedirects = false;
          scopeMaps.bookmark_users = [
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
      # Verify idm_admin is logged in (uses cached session token)
      if ! kanidm self whoami 2>/dev/null | grep -q idm_admin; then
        echo "Error: idm_admin not logged in. Run 'kanidm login -D idm_admin' first."
        exit 1
      fi

      # Create service account for Stalwart LDAP access
      kanidm service-account create stalwart_ldap "Stalwart Mail LDAP" idm_admins || true

      # Grant read access to people directory
      kanidm group add-members idm_people_pii_read stalwart_ldap || echo "WARN: Failed to add stalwart_ldap to idm_people_pii_read"

      # Generate API token for LDAP bind
      TOKEN=$(kanidm service-account api-token generate stalwart_ldap "ldap-bind" 2>&1 | tail -1)

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
