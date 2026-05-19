{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrNames
    concatMap
    concatStringsSep
    filterAttrs
    flatten
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    nameValuePair
    optional
    optionalAttrs
    optionalString
    types
    unique
    ;

  cfg = config.services.miniflux;
  provision = cfg.provision;

  secretPathType = types.either types.path types.str;

  credentialName =
    userName: feedName: key:
    let
      safeFeedName = lib.strings.sanitizeDerivationName feedName;
      hash = builtins.substring 0 8 (builtins.hashString "sha256" "${userName}-${feedName}-${key}");
    in
    "feed-${safeFeedName}-${key}-${hash}";

  nonNullAttrs = filterAttrs (_: value: value != null);

  feedToManifest =
    userName: feedName: feed:
    nonNullAttrs (
      {
        inherit (feed)
          url
          category
          title
          description
          crawler
          disabled
          ;
        site_url = feed.siteUrl;
        scraper_rules = feed.scraperRules;
        rewrite_rules = feed.rewriteRules;
        urlrewrite_rules = feed.urlRewriteRules;
        blocklist_rules = feed.blocklistRules;
        keeplist_rules = feed.keeplistRules;
        block_filter_entry_rules = feed.blockFilterEntryRules;
        keep_filter_entry_rules = feed.keepFilterEntryRules;
        ignore_entry_updates = feed.ignoreEntryUpdates;
        ignore_http_cache = feed.ignoreHttpCache;
        allow_self_signed_certificates = feed.allowSelfSignedCertificates;
        fetch_via_proxy = feed.fetchViaProxy;
        hide_globally = feed.hideGlobally;
        no_media_player = feed.noMediaPlayer;
        disable_http2 = feed.disableHttp2;
        user_agent = feed.userAgent;
        proxy_url = feed.proxyUrl;
      }
      // optionalAttrs (feed.cookieFile != null) {
        cookie_file = "$CREDENTIALS_DIRECTORY/${credentialName userName feedName "cookie"}";
      }
      // optionalAttrs (feed.usernameFile != null) {
        username_file = "$CREDENTIALS_DIRECTORY/${credentialName userName feedName "username"}";
      }
      // optionalAttrs (feed.passwordFile != null) {
        password_file = "$CREDENTIALS_DIRECTORY/${credentialName userName feedName "password"}";
      }
    );

  feedCredentials =
    userName: userCfg:
    flatten (
      mapAttrsToList (
        feedName: feed:
        optional (feed.cookieFile != null)
          "${credentialName userName feedName "cookie"}:${toString feed.cookieFile}"
        ++
          optional (feed.usernameFile != null)
            "${credentialName userName feedName "username"}:${toString feed.usernameFile}"
        ++
          optional (feed.passwordFile != null)
            "${credentialName userName feedName "password"}:${toString feed.passwordFile}"
      ) userCfg.feeds
    );

  userCredentials =
    userCfg:
    optional (userCfg.webhook.urlFile != null) "webhook-url:${toString userCfg.webhook.urlFile}"
    ++ optional (
      userCfg.webhook.secretFile != null
    ) "webhook-secret:${toString userCfg.webhook.secretFile}";

  manifestFor =
    userName: userCfg:
    pkgs.writeText "miniflux-provisioning-${userName}.json" (
      builtins.toJSON (nonNullAttrs {
        base_url = provision.apiEndpoint;
        assets = nonNullAttrs {
          css = if userCfg.stylesheet == null then null else toString userCfg.stylesheet;
          js = if userCfg.javascript == null then null else toString userCfg.javascript;
        };
        feeds = mapAttrsToList (feedToManifest userName) userCfg.feeds;
      })
    );

  bootstrapCommand =
    userCfg:
    let
      args = [
        "bootstrap-user"
        "--database-url"
        (lib.escapeShellArg cfg.config.DATABASE_URL)
        "--username"
        (lib.escapeShellArg userCfg.username)
        "--api-token-file"
        ''"$CREDENTIALS_DIRECTORY/api-token"''
        "--api-key-description"
        (lib.escapeShellArg userCfg.apiKeyDescription)
      ]
      ++ lib.optionals (userCfg.openidConnectId != null) [
        "--openid-connect-id"
        (lib.escapeShellArg userCfg.openidConnectId)
      ]
      ++ lib.optionals (userCfg.openidConnectIdFile != null) [
        "--openid-connect-id-file"
        ''"$CREDENTIALS_DIRECTORY/oidc-sub"''
      ]
      ++ lib.optionals userCfg.webhook.enable [
        "--webhook-enabled"
        "--webhook-url-file"
        ''"$CREDENTIALS_DIRECTORY/webhook-url"''
      ]
      ++ lib.optionals (userCfg.webhook.secretFile != null) [
        "--webhook-secret-file"
        ''"$CREDENTIALS_DIRECTORY/webhook-secret"''
      ];
    in
    optionalString userCfg.ensureUser ''
      ${lib.getExe provision.package} ${concatStringsSep " " args}
    '';

  serviceScript =
    userName: userCfg:
    pkgs.writeShellApplication {
      name = "miniflux-provisioning-${userName}";
      runtimeInputs = [ provision.package ];
      text = ''
        MINIFLUX_TOKEN="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/api-token")"
        export MINIFLUX_TOKEN
        ${bootstrapCommand userCfg}
        miniflux-sync sync ${manifestFor userName userCfg}
      '';
    };

  enabledUsers = filterAttrs (_: userCfg: userCfg.enable) provision.users;
  enabledUserList = mapAttrsToList (_: userCfg: userCfg) enabledUsers;
  needsBootstrap = builtins.any (userCfg: userCfg.ensureUser) enabledUserList;

  feedUrls = userCfg: mapAttrsToList (_: feed: feed.url) userCfg.feeds;

  webhookOptions = {
    options = {
      enable = mkEnableOption "Miniflux Webhook integration provisioning";

      urlFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
        description = "File containing the Miniflux Webhook integration URL.";
      };

      secretFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
        description = "Optional file containing the Miniflux Webhook HMAC secret.";
      };
    };
  };

  userOptions =
    { name, ... }:
    {
      options = {
        enable = mkEnableOption "Miniflux provisioning for this user" // {
          default = true;
        };

        ensureUser = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to bootstrap the Miniflux user and API key directly in the
            database before API reconciliation.
          '';
        };

        username = mkOption {
          type = types.str;
          default = name;
          description = "Miniflux username to provision.";
        };

        apiTokenFile = mkOption {
          type = types.nullOr secretPathType;
          default = null;
          description = "File containing the Miniflux API token for this user.";
        };

        apiKeyDescription = mkOption {
          type = types.str;
          default = "nixos-provisioning";
          description = "Description of the managed Miniflux API key.";
        };

        openidConnectId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "OIDC subject to bind to this Miniflux user.";
        };

        openidConnectIdFile = mkOption {
          type = types.nullOr secretPathType;
          default = null;
          description = "File containing the OIDC subject to bind to this Miniflux user.";
        };

        stylesheet = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Custom stylesheet to sync to the Miniflux user.";
        };

        javascript = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Custom JavaScript to sync to the Miniflux user.";
        };

        feeds = mkOption {
          type = types.attrsOf (types.submodule feedOptions);
          default = { };
          description = "Ensure-style feed declarations keyed by local stable names.";
        };

        webhook = mkOption {
          type = types.submodule webhookOptions;
          default = { };
          description = "Miniflux Webhook integration settings for Save-button actions.";
        };

        timer = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to run provisioning periodically.";
          };
          onCalendar = mkOption {
            type = types.either types.str (types.listOf types.str);
            default = "hourly";
            description = "systemd OnCalendar value for the provisioning timer.";
          };
          persistent = mkOption {
            type = types.bool;
            default = true;
            description = "Whether missed timer runs should be triggered at boot.";
          };
        };
      };
    };

  feedOptions = {
    options = {
      url = mkOption {
        type = types.str;
        description = ''
          Feed URL. This is the immutable identity used to find existing feeds.
          Changing it creates a new managed feed and leaves the old feed as an
          unmanaged orphan; change URLs manually in Miniflux first if you need to
          preserve that feed's entry/read/star state.
        '';
      };

      category = mkOption {
        type = types.str;
        description = "Miniflux category title. Missing categories are created.";
      };

      title = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      siteUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      crawler = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      scraperRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      rewriteRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      urlRewriteRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      blocklistRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      keeplistRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      blockFilterEntryRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      keepFilterEntryRules = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      disabled = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      ignoreEntryUpdates = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      ignoreHttpCache = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      allowSelfSignedCertificates = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      fetchViaProxy = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      hideGlobally = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      noMediaPlayer = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      disableHttp2 = mkOption {
        type = types.nullOr types.bool;
        default = null;
      };
      userAgent = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      proxyUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      cookieFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
      };
      usernameFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
      };
      passwordFile = mkOption {
        type = types.nullOr secretPathType;
        default = null;
      };
    };
  };
in
{
  options.services.miniflux.provision = {
    enable = mkEnableOption "ensure-style Miniflux provisioning";

    package = mkPackageOption pkgs "miniflux-sync" { };

    apiEndpoint = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        URL used by provisioning jobs to access the Miniflux API. This is not
        Miniflux BASE_URL and must be set explicitly.
      '';
    };

    users = mkOption {
      type = types.attrsOf (types.submodule userOptions);
      default = { };
      description = "Per-Miniflux-user provisioning declarations.";
    };
  };

  config = mkIf provision.enable {
    assertions = [
      {
        assertion = cfg.enable;
        message = "services.miniflux.provision requires services.miniflux.enable = true.";
      }
      {
        assertion = provision.apiEndpoint != null;
        message = "services.miniflux.provision.apiEndpoint must be set.";
      }
      {
        assertion = !needsBootstrap || cfg.config.DATABASE_URL != null;
        message = "services.miniflux.provision users with ensureUser = true require services.miniflux.config.DATABASE_URL.";
      }
      {
        assertion = enabledUsers != { };
        message = "services.miniflux.provision.users must define at least one enabled user.";
      }
      {
        assertion = builtins.all (name: builtins.match "^[A-Za-z0-9_-]+$" name != null) (
          attrNames enabledUsers
        );
        message = "services.miniflux.provision.users names must match ^[A-Za-z0-9_-]+$ for stable systemd unit names.";
      }
    ]
    ++ flatten (
      mapAttrsToList (userName: userCfg: [
        {
          assertion = userCfg.apiTokenFile != null;
          message = "services.miniflux.provision.users.${userName}.apiTokenFile must be set.";
        }
        {
          assertion = !userCfg.webhook.enable || userCfg.webhook.urlFile != null;
          message = "services.miniflux.provision.users.${userName}.webhook.urlFile must be set when webhook.enable = true.";
        }
        {
          assertion = !userCfg.ensureUser || userCfg.username != "";
          message = "services.miniflux.provision.users.${userName}.username must be non-empty when ensureUser = true.";
        }
        {
          assertion = !(userCfg.openidConnectId != null && userCfg.openidConnectIdFile != null);
          message = "services.miniflux.provision.users.${userName}: set only one of openidConnectId and openidConnectIdFile.";
        }
        {
          assertion = builtins.length (feedUrls userCfg) == builtins.length (unique (feedUrls userCfg));
          message = "services.miniflux.provision.users.${userName}: duplicate feed URLs are not allowed; URL is the feed identity.";
        }
        {
          assertion = builtins.all (feed: feed.category != "") (mapAttrsToList (_: feed: feed) userCfg.feeds);
          message = "services.miniflux.provision.users.${userName}: each feed must set a non-empty category.";
        }
      ]) enabledUsers
    );

    warnings = concatMap (
      userName:
      let
        userCfg = enabledUsers.${userName};
      in
      concatMap (
        feedName:
        let
          feed = userCfg.feeds.${feedName};
        in
        optional (feed.scraperRules != null && feed.crawler != true)
          "services.miniflux.provision.users.${userName}.feeds.${feedName}: scraperRules usually requires crawler = true."
      ) (attrNames userCfg.feeds)
    ) (attrNames enabledUsers);

    systemd.services = mapAttrs' (
      userName: userCfg:
      nameValuePair "miniflux-provisioning-${userName}" {
        description = "Provision Miniflux user ${userName}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "miniflux.service" ];
        after = [ "miniflux.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (serviceScript userName userCfg);
          User = "miniflux";
          DynamicUser = true;
          LoadCredential = [
            "api-token:${toString userCfg.apiTokenFile}"
          ]
          ++ optional (userCfg.openidConnectIdFile != null) "oidc-sub:${toString userCfg.openidConnectIdFile}"
          ++ userCredentials userCfg
          ++ feedCredentials userName userCfg;
          RuntimeDirectory = "miniflux-provisioning-${userName}";
          RuntimeDirectoryMode = "0700";
          StateDirectory = "miniflux-provisioning";
          StateDirectoryMode = "0700";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          UMask = "0077";
        };
      }
    ) enabledUsers;

    systemd.timers = mapAttrs' (
      userName: userCfg:
      nameValuePair "miniflux-provisioning-${userName}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = userCfg.timer.onCalendar;
          Persistent = userCfg.timer.persistent;
          Unit = "miniflux-provisioning-${userName}.service";
        };
      }
    ) (filterAttrs (_: userCfg: userCfg.timer.enable) enabledUsers);
  };
}
