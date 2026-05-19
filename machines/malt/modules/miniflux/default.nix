{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";

  domain = "rss.mulatta.io";
  port = 8080;
in
{
  clan.core.vars.generators.kanidm-miniflux-oidc = {
    share = true;
    files.client-secret.secret = true;
    files.env.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      client_secret=$(openssl rand -hex 32 | tr -d '\n')

      printf '%s' "$client_secret" > "$out/client-secret"
      printf 'OAUTH2_CLIENT_SECRET=%s\n' "$client_secret" > "$out/env"
    '';
  };

  clan.core.vars.generators.miniflux-seungwon = {
    files.api-token.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/api-token"
    '';
  };

  clan.core.vars.generators.miniflux-webhook = {
    files.n8n-basic-password.secret = true;
    files.webhook-url.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      password=$(openssl rand -hex 32 | tr -d '\n')
      printf '%s' "$password" > "$out/n8n-basic-password"
      printf 'https://miniflux:%s@n8n-api.mulatta.io/webhook/miniflux-save-entry' "$password" > "$out/webhook-url"
    '';
  };

  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;
    adminCredentialsFile = config.clan.core.vars.generators.kanidm-miniflux-oidc.files.env.path;
    config = {
      LISTEN_ADDR = "[${maltWgIP}]:${toString port}";
      BASE_URL = "https://${domain}";
      HTTPS = 1;
      CREATE_ADMIN = 0;
      OAUTH2_PROVIDER = "oidc";
      OAUTH2_CLIENT_ID = "miniflux";
      OAUTH2_REDIRECT_URL = "https://${domain}/oauth2/oidc/callback";
      OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://idm.mulatta.io/oauth2/openid/miniflux";
      OAUTH2_USER_CREATION = 1;
      DISABLE_LOCAL_AUTH = 1;
      # RSSHub is intentionally loopback-only; Miniflux needs to fetch those
      # local feed URLs despite its default SSRF guard.
      FETCHER_ALLOW_PRIVATE_NETWORKS = 1;
      # GitHub README feeds render multiple API-backed entries through local
      # RSSHub. Cold cache refreshes can exceed Miniflux's 20s default.
      HTTP_CLIENT_TIMEOUT = 60;
      POLLING_FREQUENCY = 30;
      CLEANUP_ARCHIVE_READ_DAYS = 60;
      CLEANUP_ARCHIVE_UNREAD_DAYS = 180;
    };

    provision = {
      enable = true;
      apiEndpoint = "http://[${maltWgIP}]:${toString port}";

      users.seungwon = {
        username = "seungwon";
        apiTokenFile = config.clan.core.vars.generators.miniflux-seungwon.files.api-token.path;
        openidConnectId = "a0ccbfe4-dfa2-44d5-ab46-cfe2701c1704";
        stylesheet = ./custom.css;
        javascript = ./custom.js;
        webhook = {
          enable = true;
          urlFile = config.clan.core.vars.generators.miniflux-webhook.files.webhook-url.path;
        };

        feeds = {
          geeknews = {
            url = "http://feeds.feedburner.com/geeknews-feed";
            category = "Dev";
            crawler = true;
            scraperRules = ".topictitle a.bold.ud, #topic_contents";
            rewriteRules = ''remove(".view-con, .view-file")'';
          };

          inuGradNotice = {
            url = "http://127.0.0.1:1200/inu/notice/grad/1348?format=json";
            category = "Notification";
          };

          kosafNotices = {
            url = "http://127.0.0.1:1200/kosaf/notices?board=0000000001/0000000001&board=0000000001/0000000003&board=0000000001/0000000008&board=0000000001/0000000010&board=0000000002/0000000023&board=0000000002/0000000025&format=json";
            category = "Notification";
          };

          githubTrendingRust = {
            title = "GitHub Trend - Rust";
            url = "http://127.0.0.1:1200/github/trending-readme/daily/rust?limit=20";
            category = "GitHub Trending";
          };

          githubTrendingPython = {
            title = "GitHub Trend - Python";
            url = "http://127.0.0.1:1200/github/trending-readme/daily/python?limit=20";
            category = "GitHub Trending";
          };

          githubTrendingGo = {
            title = "GitHub Trend - Go";
            url = "http://127.0.0.1:1200/github/trending-readme/daily/go?limit=20";
            category = "GitHub Trending";
          };

          githubTrendingTypescript = {
            title = "GitHub Trend - Typescript";
            url = "http://127.0.0.1:1200/github/trending-readme/daily/typescript?limit=20";
            category = "GitHub Trending";
          };
        };
      };
    };
  };

  # FETCHER_ALLOW_PRIVATE_NETWORKS is required for localhost RSSHub feeds, but
  # keep Miniflux from becoming a path to other private IPv4/link-local services.
  # Loopback stays allowed for RSSHub; PostgreSQL remains on AF_UNIX.
  systemd.services.miniflux.serviceConfig = {
    IPAddressAllow = [
      "127.0.0.1/32"
      "::1/128"
    ];
    IPAddressDeny = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "169.254.0.0/16"
    ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
