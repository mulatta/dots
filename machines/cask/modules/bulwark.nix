{
  config,
  lib,
  pkgs,
  ...
}:
let
  baseDomain = "mulatta.io";
  domain = "mail.${baseDomain}";
  stalwartDomain = "stalwart.${baseDomain}";
  stalwartProxyPass = "http://127.0.0.1:8080";
  stalwartProxyExtraConfig = ''
    proxy_set_header Host ${stalwartDomain};
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  '';
  stalwartProxyLocation = {
    proxyPass = stalwartProxyPass;
    extraConfig = stalwartProxyExtraConfig;
    recommendedProxySettings = false;
  };

  plugins = [
    {
      package = pkgs.bulwark-plugins.external-link-warning;
      forceEnabled = true;
      config.trustedDomains = baseDomain;
    }
    {
      package = pkgs.bulwark-plugins.external-mail-warning;
      forceEnabled = true;
      config.safeDomains = baseDomain;
    }
    {
      package = pkgs.bulwark-plugins.spam-score;
      forceEnabled = false;
      config = { };
    }
    {
      package = pkgs.bulwark-plugins.calendar-agenda;
      forceEnabled = false;
      config = { };
    }
  ];

  # shortcut: services.bulwark.plugins reads manifests during evaluation (IFD),
  # so assemble the registry in a build; drop once NixOS/nixpkgs#561326 lands.
  pluginDirectory = pkgs.runCommand "bulwark-plugins" { nativeBuildInputs = [ pkgs.jq ]; } ''
    mkdir -p "$out/config"
    ${lib.concatMapStringsSep "\n" (plugin: ''
      # Without bundleHash the client skips its integrity check.
      jq --arg hash "$(sha256sum ${plugin.package}/index.js | cut -d' ' -f1)" \
        '. + { enabled: true, forceEnabled: ${lib.boolToString plugin.forceEnabled}, bundleHash: $hash }' \
        ${plugin.package}/manifest.json > "${plugin.package.pluginName}.json"
      ln -s ${plugin.package}/index.js "$out/${plugin.package.pluginName}.js"
      ${lib.optionalString (plugin.config != { }) ''
        ln -s ${(pkgs.formats.json { }).generate "${plugin.package.pluginName}.json" plugin.config} \
          "$out/config/${plugin.package.pluginName}.json"
      ''}
    '') plugins}
    jq -s '{ plugins: . }' ${
      lib.concatMapStringsSep " " (plugin: "${plugin.package.pluginName}.json") plugins
    } \
      > "$out/registry.json"
  '';

  adminConfigDir = config.systemd.services.bulwark.environment.ADMIN_CONFIG_DIR;
in
{
  services.bulwark = {
    enable = true;
    # Next normalizes loopback rewrites to localhost; any other bind host makes
    # next-intl rewrites look external and get proxied over TLS (EPROTO).
    hostname = "localhost";
    updateCheck.enabled = false;

    settings = {
      jmapServerUrl = "https://${domain}";
      sessionSecretFile = "/run/credentials/bulwark.service/session-secret";
      settingsSyncEnabled = true;
      autoSsoEnabled = false;

      oauth = {
        enabled = true;
        clientId = "bulwark-webmail";
        # Browser-side discovery runs from the webmail origin. Proxy Stalwart's
        # metadata through that origin so CORS does not hide the SSO button.
        issuerUrl = "https://${domain}";
        only = true;
        scopes = "openid offline_access urn:ietf:params:jmap:core urn:ietf:params:jmap:mail urn:ietf:params:jmap:submission urn:ietf:params:jmap:vacationresponse urn:ietf:params:jmap:calendars urn:ietf:params:jmap:contacts";
      };
    };

    policies.forceEnabledPlugins = map (plugin: plugin.package.pluginName) (
      builtins.filter (plugin: plugin.forceEnabled) plugins
    );
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    locations = {
      "/" = {
        proxyPass = "http://localhost:${toString config.services.bulwark.port}";
        proxyWebsockets = true;
      };
      "= /.well-known/oauth-authorization-server" = stalwartProxyLocation;
      "= /.well-known/openid-configuration" = stalwartProxyLocation;
      "= /.well-known/caldav" = stalwartProxyLocation;
      "= /.well-known/carddav" = stalwartProxyLocation;
      "= /.well-known/jmap" = stalwartProxyLocation // {
        proxyPass = "${stalwartProxyPass}/jmap/session";
        extraConfig = stalwartProxyExtraConfig + ''
          proxy_set_header Accept-Encoding "";
          sub_filter "https://${stalwartDomain}/" "https://${domain}/";
          sub_filter_once off;
          sub_filter_types application/json;
        '';
      };
      "/dav/" = stalwartProxyLocation;
      "/jmap/" = stalwartProxyLocation // {
        proxyWebsockets = true;
        extraConfig = stalwartProxyExtraConfig + ''
          client_max_body_size 50M;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };
  };

  systemd.services.bulwark = {
    after = [
      "kanidm.service"
      "stalwart.service"
      "stalwart-provision.service"
    ];
    wants = [
      "kanidm.service"
      "stalwart.service"
    ];
    requires = [ "stalwart-provision.service" ];
    # Signed bundles are the trust root for privileged plugins; the read-only
    # admin config cannot hold a lazily generated key.
    environment.PLUGIN_SIGNING_KEY_FILE = "/run/credentials/bulwark.service/plugin-signing-key";
    serviceConfig = {
      LoadCredential = [
        "session-secret:${config.clan.core.vars.generators.bulwark-webmail.files.session-secret.path}"
        "plugin-signing-key:${config.clan.core.vars.generators.bulwark-plugin-signing.files.key.path}"
      ];
      BindReadOnlyPaths = [
        "${pluginDirectory}:${adminConfigDir}/plugins"
        "${pluginDirectory}/config:${adminConfigDir}/plugin-config"
      ];
      # Port 3000 needs no capability; drop the module's CAP_NET_BIND_SERVICE.
      AmbientCapabilities = lib.mkForce [ "" ];
      CapabilityBoundingSet = lib.mkForce [ "" ];
      StateDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "5s";
      MemoryHigh = "256M";
      MemoryMax = "512M";
    };
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

  clan.core.vars.generators.bulwark-webmail = {
    files.session-secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/session-secret"
    '';
  };

  clan.core.vars.generators.bulwark-plugin-signing = {
    files.key.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl genpkey -algorithm ed25519 -out "$out/key"
    '';
  };
}
