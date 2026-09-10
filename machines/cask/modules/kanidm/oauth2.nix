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

  # Keep runtime closures small while tying logos to package source revisions.

  iconBundle = pkgs.fetchzip {
    url = "https://github.com/mulatta/dots/releases/download/oauth-icons-v1/kanidm-oauth-icons-v1.zip";
    hash = "sha256-DZppoLkWXApmcliJT5RZjji2KrVKxthT5r8byNGZ9GA=";
    stripRoot = false;
  };

  icons = {
    bulwark = "${iconBundle}/bulwark.svg";
    gitea = "${iconBundle}/gitea.svg";
    homeassistant = "${iconBundle}/homeassistant.svg";
    jellyfin = "${iconBundle}/jellyfin.svg";
    linkwarden = "${iconBundle}/linkwarden.png";
    miniflux = "${iconBundle}/miniflux.svg";
    n8n = "${iconBundle}/n8n.svg";
    nextcloud = "${iconBundle}/nextcloud.svg";
    paperless = "${iconBundle}/paperless.svg";
    restate = "${iconBundle}/restate.svg";
    stalwart = "${iconBundle}/stalwart.png";
    zotero = "${iconBundle}/zotero.svg";
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
      imageFile = icons.gitea;
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
      imageFile = icons.restate;
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
      imageFile = icons.zotero;
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
      imageFile = icons.jellyfin;
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
      imageFile = icons.homeassistant;
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

  generators = {
    kanidm-miniflux-oidc = {
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

    kanidm-paperless-oidc = {
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

    kanidm-linkwarden-oidc = {
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

    kanidm-jellyfin-oidc = {
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

  };
}
