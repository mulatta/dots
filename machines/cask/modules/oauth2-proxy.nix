{
  config,
  pkgs,
  ...
}:
let
  kanidmDomain = "idm.mulatta.io";
  n8nDomain = "n8n.mulatta.io";
  n8nApiDomain = "n8n-api.mulatta.io";

  # These proxies are public OIDC clients, so the only generated secret is the
  # cookie-signing key; the client secret is an unused placeholder.
  mkOauth2ProxySecret = {
    files."env" = {
      secret = true;
      owner = "oauth2-proxy";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      COOKIE_SECRET=$(openssl rand -hex 16)
      cat > "$out/env" <<EOF
      OAUTH2_PROXY_COOKIE_SECRET=$COOKIE_SECRET
      OAUTH2_PROXY_CLIENT_SECRET=unused-public-client
      EOF
    '';
  };
in
{
  # oauth2-proxy needs kanidm to be running for OIDC discovery
  systemd.services.oauth2-proxy = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
  clan.core.vars.generators.oauth2-proxy = mkOauth2ProxySecret;

  services.oauth2-proxy = {
    enable = true;
    provider = "oidc";
    clientID = "n8n";
    keyFile = config.clan.core.vars.generators.oauth2-proxy.files."env".path;

    cookie = {
      # Pin the cookie to the n8n vhost. A wildcard `.mulatta.io`
      # domain would ship the oauth2-proxy session to every sibling
      # site's JavaScript, so an XSS on any mulatta.io subdomain could
      # hijack the n8n session. n8n.mulatta.io is the only consumer,
      # so there is no need to share.
      domain = "n8n.mulatta.io";
      secure = true;
      httpOnly = true;
      refresh = "1h";
      # Hard cap the session at 72h. cookie.refresh (1h) keeps the
      # user signed in as long as kanidm still considers the token
      # valid, so this mostly caps the blast radius of a stolen
      # cookie — 3 days vs 30 days — without hurting everyday UX.
      expire = "72h";
    };

    extraConfig = {
      oidc-issuer-url = "https://${kanidmDomain}/oauth2/openid/n8n";
      redirect-url = "https://${n8nDomain}/oauth2/callback";
      scope = "openid email profile";
      set-xauthrequest = "true";
      pass-access-token = "true";
      pass-authorization-header = "true";
      set-authorization-header = "true";
      skip-provider-button = "true";
      skip-auth-route = [
        "^/webhook"
        "^/webhook-test"
        "^/healthz"
      ];
      upstream = "http://malt.n:5678";
      http-address = "127.0.0.1:4180";
      email-domain = "mulatta.io";
      code-challenge-method = "S256";
      insecure-oidc-allow-unverified-email = "true";
    };
  };
  services.nginx.virtualHosts = {
    ${n8nDomain} = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      mulatta.securityHeaders = "deny";
      locations."/" = {
        proxyPass = "http://127.0.0.1:4180";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 50M;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    ${n8nApiDomain} = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      mulatta.securityHeaders = "deny";
      locations."~ ^/(webhook(-test)?|healthz)" = {
        proxyPass = "http://malt.n:5678";
        proxyWebsockets = true;
        extraConfig = ''
          # SECURITY: Prevent header injection - clear all auth headers
          proxy_set_header X-Email "";
          proxy_set_header X-Auth-Request-Email "";
          proxy_set_header X-Auth-Request-User "";
          proxy_set_header X-Access-Token "";

          client_max_body_size 50M;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
      locations."/".return = "404";
    };

  };
}
