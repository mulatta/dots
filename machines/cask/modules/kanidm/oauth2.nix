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
    url = "https://github.com/mulatta/dots/releases/download/oauth-icons-v2/kanidm-oauth-icons-v2.zip";
    hash = "sha256-apaV+wlaaAoXFTycFdjdGVEksDG163PypP5QDa4NWTY=";
    stripRoot = false;
  };

  icons = {
    neko = "${iconBundle}/neko.png";
    hermes = "${iconBundle}/hermes.svg";
    sparkyfitness = "${iconBundle}/sparkyfitness.png";
    trek = "${iconBundle}/trek.svg";
    bulwark = "${iconBundle}/bulwark.svg";
    gitea = "${iconBundle}/gitea.svg";
    homeassistant = "${iconBundle}/homeassistant.svg";
    jellyfin = "${iconBundle}/jellyfin.svg";
    linkwarden = "${iconBundle}/linkwarden.png";
    miniflux = "${iconBundle}/miniflux.svg";
    nextcloud = "${iconBundle}/nextcloud.svg";
    paperless = "${iconBundle}/paperless.svg";
    stalwart = "${iconBundle}/stalwart.png";
    zotero = "${iconBundle}/zotero.svg";
  };

in
{
  clients = {
    # Neko requires a confidential client and sends S256 PKCE.
    neko = {
      displayName = "Neko";
      imageFile = icons.neko;
      originUrl = "https://neko.${baseDomain}/api/oauth/callback";
      originLanding = "https://neko.${baseDomain}";
      public = false;
      enableLocalhostRedirects = false;
      preferShortUsername = true;
      basicSecretFile = config.clan.core.vars.generators.kanidm-neko-oidc.files.client-secret.path;
      scopeMaps.neko_users = [
        "openid"
        "email"
        "profile"
      ];
      # Neko reads isAdmin, not groups; an array is not accepted as true.
      claimMaps.isAdmin = {
        joinType = "csv";
        valuesByGroup.neko_admins = [ "true" ];
      };
    };

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

    # Hermes verifies OIDC ID tokens and uses S256 PKCE without a client secret.
    # Scope maps are the access allow-list for this agent-control dashboard.
    hermes = {
      displayName = "Hermes Dashboard";
      imageFile = icons.hermes;
      originUrl = [ "https://hermes.${baseDomain}/auth/callback" ];
      originLanding = "https://hermes.${baseDomain}";
      public = true;
      enableLocalhostRedirects = false;
      scopeMaps.hermes_users = [
        "openid"
        "profile"
        "email"
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

    sparkyfitness = {
      displayName = "SparkyFitness";
      imageFile = icons.sparkyfitness;
      originUrl = [
        "https://fitness.${baseDomain}"
        "https://fitness.${baseDomain}/api/auth/sso/callback/kanidm"
      ];
      originLanding = "https://fitness.${baseDomain}";
      public = false;
      enableLocalhostRedirects = false;
      preferShortUsername = true;
      basicSecretFile = config.clan.core.vars.generators.kanidm-sparkyfitness-oidc.files.secret.path;
      scopeMaps.fitness_users = [
        "openid"
        "email"
        "profile"
        "groups"
      ];
    };

    # TREK - confidential client; sends PKCE and posts the client secret.
    trek = {
      displayName = "TREK";
      imageFile = icons.trek;
      originUrl = [
        "https://trek.${baseDomain}"
        "https://trek.${baseDomain}/api/auth/oidc/callback"
      ];
      originLanding = "https://trek.${baseDomain}";
      public = false;
      enableLocalhostRedirects = false;
      preferShortUsername = true;
      basicSecretFile = config.clan.core.vars.generators.kanidm-trek-oidc.files.secret.path;
      scopeMaps.trek_users = [
        "openid"
        "email"
        "profile"
        "groups_name"
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
    kanidm-neko-oidc = {
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
        printf 'NEKO_MEMBER_OAUTH_CLIENT_SECRET=%s\n' "$client_secret" > "$out/env"
      '';
    };

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

    kanidm-sparkyfitness-oidc = {
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

    kanidm-trek-oidc = {
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
