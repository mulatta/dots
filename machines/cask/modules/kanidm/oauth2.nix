{
  pkgs,
  config,
  baseDomain,
}:
let
  bulwarkWebmailDomain = config.services.bulwark-webmail.nginx.hostName;
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

    # Linkwarden 2.14.0 - from official repo
    linkwarden = pkgs.fetchurl {
      name = "linkwarden.png";
      url = "https://raw.githubusercontent.com/linkwarden/linkwarden/v2.14.0/assets/logo.png";
      hash = "sha256-zCaHvIYW0HV+z5mJquAPvNbKBgirYFTyXN1qD+K9Ayw=";
    };

  };
in
{
  clients = {
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

    # Gitea - confidential client. Kanidm scope maps are the login
    # allow-list; Gitea maps the admins claim on every OIDC login.
    gitea = {
      displayName = "Gitea";
      originUrl = [
        "https://git.${baseDomain}"
        "https://git.${baseDomain}/user/oauth2/kanidm/callback"
      ];
      originLanding = "https://git.${baseDomain}";
      public = false;
      enableLocalhostRedirects = false;
      # Gitea's confidential OIDC client does not send a PKCE challenge.
      allowInsecureClientDisablePkce = true;
      preferShortUsername = true;
      basicSecretFile = config.clan.core.vars.generators.kanidm-gitea-oidc.files.kanidm-secret.path;
      scopeMaps = {
        admins = [
          "openid"
          "email"
          "profile"
          "groups_name"
          "ssh_publickeys"
        ];
        git_users = [
          "openid"
          "email"
          "profile"
          "groups_name"
          "ssh_publickeys"
        ];
      };
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
}
