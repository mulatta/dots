{ config, pkgs, ... }:
let
  baseDomain = "mulatta.io";
  domain = "mail.${baseDomain}";
  oldDomain = "webmail.${baseDomain}";
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
in
{
  services.bulwark-webmail = {
    enable = true;
    jmapServerUrl = "https://${domain}";
    sessionSecretFile = config.clan.core.vars.generators.bulwark-webmail.files.session-secret.path;
    settingsSync.enable = true;

    oauth = {
      enable = true;
      clientId = "bulwark-webmail";
      # Browser-side discovery runs from the webmail origin. Proxy Stalwart's
      # metadata through that origin so CORS does not hide the SSO button.
      issuerUrl = "https://${domain}";
      only = true;
      autoSso = false;
      scopes = "openid offline_access urn:ietf:params:jmap:core urn:ietf:params:jmap:mail urn:ietf:params:jmap:submission urn:ietf:params:jmap:vacationresponse urn:ietf:params:jmap:calendars urn:ietf:params:jmap:contacts";
    };

    nginx = {
      enable = true;
      hostName = domain;
      enableACME = true;
      forceSSL = true;
    };
  };

  services.nginx.virtualHosts.${domain}.locations = {
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

  services.nginx.virtualHosts.${oldDomain} = {
    enableACME = true;
    forceSSL = true;
    globalRedirect = domain;
  };

  systemd.services.bulwark-webmail = {
    after = [
      "kanidm.service"
      "stalwart.service"
      "stalwart-bulwark-oauth-client.service"
    ];
    wants = [
      "kanidm.service"
      "stalwart.service"
      "stalwart-bulwark-oauth-client.service"
    ];
    serviceConfig = {
      MemoryHigh = "256M";
      MemoryMax = "512M";
    };
  };

  clan.core.vars.generators.bulwark-webmail = {
    files.session-secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/session-secret"
    '';
  };
}
