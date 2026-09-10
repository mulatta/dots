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

  oauth2 = import ./oauth2.nix {
    inherit pkgs config baseDomain;
  };
in
{
  services.kanidm = {
    server.enable = true;
    client.enable = true;
    package = pkgs.kanidmWithSecretProvisioning_1_11;

    # Used by the stalwart token script (kanidm CLI).
    client.settings = {
      uri = "https://${domain}";
    };

    server.settings = {
      inherit domain;
      origin = "https://${domain}";
      bindaddress = "${bindAddress}:${toString port}";

      # LDAP server for IMAP/SMTP authentication (Stalwart, etc.)
      ldapbindaddress = "127.0.0.1:3636";

      # Serve TLS on the listener from the ACME certs (kanidm requires its own TLS).
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

      groups = {
        mail_users = {
          members = [
            "seungwon"
            "n8n_notify"
            "gitea_notify"
            "noa"
          ];
        };
        cloud_users = {
          members = [
            "seungwon"
            "n8n_bot"
          ];
        };
        automation_users = {
          members = [ "seungwon" ];
        };
        task_users = {
          members = [ "seungwon" ];
        };
        paperless_users = {
          members = [ "seungwon" ];
        };
        rss_users = {
          members = [ "seungwon" ];
        };
        bookmark_users = {
          members = [ "seungwon" ];
        };
        git_users = {
          members = [ "seungwon" ];
        };
        zotero_users = {
          members = [ "seungwon" ];
        };
        media_users = {
          members = [ "seungwon" ];
        };
        homeassistant_users = {
          members = [ "seungwon" ];
        };
        chat_users = {
          members = [ "seungwon" ];
        };
        admins = {
          members = [ "seungwon" ];
        };
        # Agents - automated agent identities (e.g. noa). Members
        # authenticate to stalwart IMAP via kanidm POSIX password (LDAP
        # simple bind) and have no other app SSO scope by default; the
        # group exists to scope future agent-only policies.
        agents = {
          members = [ "noa" ];
        };
        # Bots - non-interactive automation identities. Distinct from
        # `agents` (which receive mail) because bots only need OIDC
        # bootstrap to provision a downstream user, then operate via
        # service-issued credentials (e.g. Nextcloud app passwords).
        # Reserved for future bot-only account-policy carve-outs; no
        # policy attached today.
        bots = {
          members = [ "n8n_bot" ];
        };
      };

      persons = {
        seungwon = {
          displayName = "Seungwon";
          mailAddresses = [
            "seungwon@${baseDomain}"
            # Operational aliases terminate in the primary operator mailbox;
            # no service needs separate mailbox credentials for these roles.
            "acme@${baseDomain}"
            "billings@${baseDomain}"
            "postmaster@${baseDomain}"
            "security@${baseDomain}"
          ];
        };
        n8n_notify = {
          displayName = "n8n notify";
          mailAddresses = [ "n8n@${baseDomain}" ];
        };
        # SMTP-only identity. Keep it outside git_users so mail credentials
        # cannot be used for interactive Gitea login.
        gitea_notify = {
          displayName = "Gitea notifications";
          mailAddresses = [ "git@${baseDomain}" ];
        };
        # n8n automation bot. OIDC into Nextcloud once to provision the
        # downstream user; thereafter n8n authenticates via a Nextcloud
        # app password (stored in n8n credentials), so kanidm is not in
        # the hot path. Mail intentionally omitted — n8n_notify owns
        # outbound notification mail; this account writes to Nextcloud.
        n8n_bot = {
          displayName = "n8n automation bot";
        };
        # Personal assistant agent. Receives mail forwarded from
        # seungwon's flagged messages via sieve and is read by mbsync
        # on malt. External SMTP delivery is rejected at the stalwart
        # MTA RCPT stage (only seungwon@ may originate mail to noa@).
        noa = {
          displayName = "Noa";
          mailAddresses = [ "noa@${baseDomain}" ];
        };
      };

      # OAuth2/OIDC clients
      systems.oauth2 = oauth2.clients;
    };
  };

  # ACME certificate for Kanidm
  security.acme.certs.${domain} = {
    group = "nginx";
    webroot = "/var/lib/acme/acme-challenge";
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

  # Public nginx vhost; reverse-proxies all traffic to the kanidm listener.
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
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
      if ! kanidm self whoami -D idm_admin 2>/dev/null | grep -q idm_admin; then
        echo "Error: idm_admin not logged in. Run 'kanidm login -D idm_admin' first."
        exit 1
      fi

      # Create service account for Stalwart LDAP access
      kanidm service-account create -D idm_admin stalwart_ldap "Stalwart Mail LDAP" idm_admins || true

      # Grant read access to people directory
      kanidm group add-members -D idm_admin idm_people_pii_read stalwart_ldap || echo "WARN: Failed to add stalwart_ldap to idm_people_pii_read"

      # Generate API token for LDAP bind
      TOKEN=$(kanidm service-account api-token generate -D idm_admin stalwart_ldap "ldap-bind" 2>&1 | tail -1)

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

  clan.core.vars.generators = oauth2.generators;
}
