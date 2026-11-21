{
  self,
  config,
  pkgs,
  ...
}:
let
  cask = self.nixosConfigurations.cask.config.networking.naru;
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

  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;
    adminCredentialsFile = config.clan.core.vars.generators.kanidm-miniflux-oidc.files.env.path;
    config = {
      LISTEN_ADDR = "[::]:${toString port}";
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
      # Cold-cache GitHub README feeds through RSSHub exceed Miniflux's 20s default.
      HTTP_CLIENT_TIMEOUT = 120;
      POLLING_FREQUENCY = 30;
      # A feed parked after 3 transient errors is never repolled; 0 lets it recover.
      POLLING_PARSING_ERROR_LIMIT = 0;
      CLEANUP_ARCHIVE_READ_DAYS = 60;
      CLEANUP_ARCHIVE_UNREAD_DAYS = 180;
    };

    provision = {
      enable = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.miniflux-sync;
      apiEndpoint = "http://[::1]:${toString port}";

      users.seungwon = {
        username = "seungwon";
        apiTokenFile = config.clan.core.vars.generators.miniflux-seungwon.files.api-token.path;
        openidConnectId = "a0ccbfe4-dfa2-44d5-ab46-cfe2701c1704";
        stylesheet = ./custom.css;
        javascript = ./custom.js;
        feeds = {
          geeknews = {
            url = "http://feeds.feedburner.com/geeknews-feed";
            category = "Dev";
            crawler = true;
            scraperRules = ".topictitle a.bold.ud, #topic_contents";
            rewriteRules = ''remove(".view-con, .view-file")'';
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
  # keep Miniflux from becoming a path to other private/link-local services.
  # Loopback stays allowed for RSSHub; PostgreSQL remains on AF_UNIX.
  systemd.services.miniflux.serviceConfig = {
    IPAddressAllow = [
      "127.0.0.1/32"
      "::1/128"
      # The private-network deny also covers proxy replies. Permit only
      # cask on both address families without reopening the entire mesh.
      "${cask.ipv4}/32"
      "${cask.ipv6}/128"
    ];
    IPAddressDeny = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "169.254.0.0/16"
      # IPv6 ULA (covers the WireGuard fd28::/.. mesh) and link-local
      "fc00::/7"
      "fe80::/10"
    ];
  };

  networking.firewall.extraInputRules = ''
    iifname "tinc.naru" ip saddr ${cask.ipv4} tcp dport ${toString port} accept
    iifname "tinc.naru" ip6 saddr ${cask.ipv6} tcp dport ${toString port} accept
  '';
}
