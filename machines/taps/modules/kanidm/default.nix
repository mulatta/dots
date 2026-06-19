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
  bulwarkWebmailDomain = "mail.${baseDomain}";
  bulwarkWebmailLocales = [
    "cs"
    "en"
    "fr"
    "de"
    "es"
    "it"
    "ja"
    "ko"
    "lv"
    "nl"
    "pl"
    "pt"
    "ru"
    "tr"
    "uk"
    "zh"
  ];

  # OAuth2 client logos (pinned to package versions)
  icons = {
    # Nextcloud 32.0.3 - pinned to nextcloud.com repo commit
    nextcloud = pkgs.fetchurl {
      name = "nextcloud.svg";
      url = "https://raw.githubusercontent.com/nextcloud/nextcloud.com/35505202100647f0363b3e12efd66a19bf060d6f/assets/img/logo/logo_nextcloud_blue.svg";
      hash = "sha256-vKr7ILKaS1emP3/TcoctglXugvFP+hEQthXS4cGRXzY=";
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

    # Bulwark Webmail - from official branding assets
    bulwark = pkgs.fetchurl {
      name = "bulwark.svg";
      url = "https://raw.githubusercontent.com/bulwarkmail/webmail/main/public/branding/Bulwark_Logo_with_Lettering_Dark_Color.svg";
      hash = "sha256-5T3qz1QAqoMkfTXxln4ThSU/16QgV1/DwlIf8QVCaVo=";
    };

    # Paperless-ngx (client branding) - from simple-icons repo (pinned commit)
    paperless = pkgs.fetchurl {
      name = "paperlessngx.svg";
      url = "https://raw.githubusercontent.com/simple-icons/simple-icons/faa4f93283a90f0196f3d320968bd38972a27894/icons/paperlessngx.svg";
      hash = "sha256-biWHNSGTTOHM1EyVWNXR5mNxCC9XallZCNfCHDUC6GM=";
    };

    # Miniflux - from official project static icons
    miniflux = pkgs.fetchurl {
      name = "miniflux.png";
      url = "https://raw.githubusercontent.com/miniflux/v2/main/internal/ui/static/bin/icon-512.png";
      hash = "sha256-X8ujVAT/zYmU1hXfCWU8AIEvK01lOetRHfT5481PjFo=";
    };

    # Vikunja - from simple-icons repo (pinned commit)
    vikunja = pkgs.fetchurl {
      name = "vikunja.svg";
      url = "https://raw.githubusercontent.com/simple-icons/simple-icons/faa4f93283a90f0196f3d320968bd38972a27894/icons/vikunja.svg";
      hash = "sha256-1H4T2rBSBVFcqZfw4z1rVwsBUX5PkwBD5YAK+Phg+Vw=";
    };

    # Linkwarden 2.14.0 - from official repo
    linkwarden = pkgs.fetchurl {
      name = "linkwarden.png";
      url = "https://raw.githubusercontent.com/linkwarden/linkwarden/v2.14.0/assets/logo.png";
      hash = "sha256-zCaHvIYW0HV+z5mJquAPvNbKBgirYFTyXN1qD+K9Ayw=";
    };

  };
in
{
  services.kanidm = {
    server.enable = true;
    client.enable = true;
    package = pkgs.kanidmWithSecretProvisioning_1_10;

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
        zotero_users = {
          members = [ "seungwon" ];
        };
        media_users = {
          members = [ "seungwon" ];
        };
        homeassistant_users = {
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
      systems.oauth2 = {
        # Stalwart Mail - public client with PKCE
        stalwart = {
          displayName = "Stalwart Mail";
          imageFile = icons.stalwart;
          originUrl = "https://stalwart.${baseDomain}";
          originLanding = "https://stalwart.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.mail_users = [
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

        # Restate admin UI/API via oauth2-proxy. Runtime ingress stays on
        # a separate vhost so public invocations can use workload-specific auth.
        restate = {
          displayName = "Restate Orchestration";
          originUrl = [
            "https://restate.${baseDomain}"
            "https://restate.${baseDomain}/oauth2/callback"
          ];
          originLanding = "https://restate.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.automation_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # zhost (self-hosted Zotero) — gates only the enrollment /login path
        # via oauth2-proxy; the sync API itself is public + API-key-authed.
        zhost = {
          displayName = "Zotero (zhost)";
          originUrl = [
            "https://zotero.${baseDomain}"
            "https://zotero.${baseDomain}/oauth2/callback"
          ];
          originLanding = "https://zotero.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          scopeMaps.zotero_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        paperless = {
          displayName = "Paperless";
          imageFile = icons.paperless;
          originUrl = [
            "https://paperless.${baseDomain}"
            "https://paperless.${baseDomain}/accounts/oidc/kanidm/login/callback/"
          ];
          originLanding = "https://paperless.${baseDomain}";
          public = false;
          enableLocalhostRedirects = false;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-paperless-oidc.files.secret.path;
          scopeMaps.paperless_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        miniflux = {
          displayName = "Miniflux";
          imageFile = icons.miniflux;
          originUrl = [
            "https://rss.${baseDomain}"
            "https://rss.${baseDomain}/oauth2/oidc/callback"
          ];
          originLanding = "https://rss.${baseDomain}";
          public = false;
          enableLocalhostRedirects = false;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-miniflux-oidc.files.client-secret.path;
          scopeMaps.rss_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        # Linkwarden - confidential client. NextAuth.js uses the
        # provider callback below and needs RS256 from Kanidm.
        linkwarden = {
          displayName = "Linkwarden";
          imageFile = icons.linkwarden;
          originUrl = [
            "https://links.${baseDomain}"
            "https://links.${baseDomain}/api/v1/auth/callback/authentik"
          ];
          originLanding = "https://links.${baseDomain}";
          public = false;
          enableLocalhostRedirects = false;
          allowInsecureClientDisablePkce = true;
          enableLegacyCrypto = true;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-linkwarden-oidc.files.secret.path;
          scopeMaps.bookmark_users = [
            "openid"
            "email"
            "profile"
          ];
        };
        jellyfin = {
          displayName = "Jellyfin";
          originUrl = [
            "https://video.${baseDomain}"
            "https://video.${baseDomain}/sso/OID/redirect/kanidm"
            "https://video.${baseDomain}/sso/OID/r/kanidm"
          ];
          originLanding = "https://video.${baseDomain}";
          public = false;
          enableLocalhostRedirects = false;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-jellyfin-oidc.files.secret.path;
          scopeMaps = {
            admins = [
              "openid"
              "email"
              "profile"
              "groups"
            ];
            media_users = [
              "openid"
              "email"
              "profile"
              "groups"
            ];
          };
        };

        homeassistant = {
          displayName = "Home Assistant";
          originUrl = [
            "https://home.${baseDomain}/auth/oidc/welcome"
            "https://home.${baseDomain}/auth/oidc/callback"
          ];
          originLanding = "https://home.${baseDomain}";
          public = true;
          enableLocalhostRedirects = false;
          enableLegacyCrypto = true;
          preferShortUsername = true;
          scopeMaps = {
            admins = [
              "openid"
              "email"
              "profile"
              "groups"
            ];
            homeassistant_users = [
              "openid"
              "email"
              "profile"
              "groups"
            ];
          };
        };

        # Vikunja - confidential client. Vikunja's OIDC implementation
        # follows the Authorization Code Flow and the upstream docs only
        # describe confidential clients, so we use basicSecretFile here.
        # Vikunja 2.3 does not send a PKCE code_challenge, so we disable
        # kanidm's enforced PKCE mode for this client. The confidential
        # client_secret still protects the token exchange.
        vikunja = {
          displayName = "Vikunja";
          imageFile = icons.vikunja;
          originUrl = "https://tasks.${baseDomain}/auth/openid/kanidm";
          originLanding = "https://tasks.${baseDomain}";
          public = false;
          enableLocalhostRedirects = false;
          allowInsecureClientDisablePkce = true;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-vikunja-oidc.files.secret.path;
          scopeMaps.task_users = [
            "openid"
            "email"
            "profile"
          ];
        };

        bulwark-webmail = {
          displayName = "Bulwark Webmail";
          imageFile = icons.bulwark;
          originUrl = [
            "https://${bulwarkWebmailDomain}"
          ]
          ++ map (locale: "https://${bulwarkWebmailDomain}/${locale}/auth/callback") bulwarkWebmailLocales;
          originLanding = "https://${bulwarkWebmailDomain}";
          public = false;
          enableLocalhostRedirects = false;
          preferShortUsername = true;
          basicSecretFile = config.clan.core.vars.generators.kanidm-bulwark-webmail-oidc.files.secret.path;
          scopeMaps.mail_users = [
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

  # Public nginx vhost; reverse-proxies all traffic to the kanidm listener.
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

  clan.core.vars.generators.kanidm-miniflux-oidc = {
    share = true;
    files.client-secret = {
      secret = true;
      owner = "kanidm";
    };
    files.env.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      client_secret=$(openssl rand -hex 32 | tr -d '\n')

      printf '%s' "$client_secret" > "$out/client-secret"
      printf 'OAUTH2_CLIENT_SECRET=%s\n' "$client_secret" > "$out/env"
    '';
  };

  clan.core.vars.generators.kanidm-paperless-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  clan.core.vars.generators.kanidm-linkwarden-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };
  clan.core.vars.generators.kanidm-jellyfin-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  # Shared OIDC client secret for the Vikunja relying party on malt.
  # `share = true` makes clan distribute the same value to both machines,
  # so kanidm provisions the client with basicSecretFile and vikunja reads
  # the identical secret via LoadCredential at preStart.
  clan.core.vars.generators.kanidm-vikunja-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  clan.core.vars.generators.kanidm-bulwark-webmail-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "kanidm";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };
}
