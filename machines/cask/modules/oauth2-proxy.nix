{
  config,
  lib,
  pkgs,
  ...
}:
let
  securityHeadersConfig = ''
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';
  kanidmDomain = "idm.mulatta.io";
  n8nDomain = "n8n.mulatta.io";
  n8nApiDomain = "n8n-api.mulatta.io";
  restateDomain = "restate.mulatta.io";
  restateApiDomain = "restate-api.mulatta.io";
  weechatDomain = "chat.mulatta.io";

  restateOauth2Args = [
    "--provider=oidc"
    "--client-id=restate"
    "--oidc-issuer-url=https://${kanidmDomain}/oauth2/openid/restate"
    "--redirect-url=https://${restateDomain}/oauth2/callback"
    "--scope=openid email profile"
    "--email-domain=mulatta.io"
    "--code-challenge-method=S256"
    "--insecure-oidc-allow-unverified-email=true"
    "--set-xauthrequest=true"
    "--pass-access-token=true"
    "--pass-authorization-header=true"
    "--set-authorization-header=true"
    "--reverse-proxy=true"
    "--skip-provider-button=true"
    "--cookie-domain=${restateDomain}"
    "--cookie-name=_oauth2_proxy_restate"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=72h"
    "--upstream=http://malt.n:9070"
    "--http-address=127.0.0.1:4181"
  ];

  weechatOauth2Args = [
    "--provider=oidc"
    "--client-id=weechat"
    "--oidc-issuer-url=https://${kanidmDomain}/oauth2/openid/weechat"
    "--redirect-url=https://${weechatDomain}/oauth2/callback"
    "--scope=openid email profile"
    "--email-domain=mulatta.io"
    "--code-challenge-method=S256"
    "--insecure-oidc-allow-unverified-email=true"
    "--set-xauthrequest=true"
    "--pass-access-token=true"
    "--pass-authorization-header=true"
    "--set-authorization-header=true"
    "--reverse-proxy=true"
    "--skip-provider-button=true"
    "--cookie-domain=${weechatDomain}"
    "--cookie-name=_oauth2_proxy_weechat"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=72h"
    "--upstream=static://202"
    "--http-address=127.0.0.1:4183"
  ];

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
  clan.core.vars.generators.oauth2-proxy-restate = mkOauth2ProxySecret;
  clan.core.vars.generators.oauth2-proxy-weechat = mkOauth2ProxySecret;

  systemd.services.oauth2-proxy-restate = {
    description = "OAuth2 Proxy for Restate";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ config.clan.core.vars.generators.oauth2-proxy-restate.files."env".path ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = config.clan.core.vars.generators.oauth2-proxy-restate.files."env".path;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs restateOauth2Args}";
      Restart = "always";
    };
  };

  systemd.services.oauth2-proxy-weechat = {
    description = "OAuth2 Proxy for WeeChat";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ config.clan.core.vars.generators.oauth2-proxy-weechat.files."env".path ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = config.clan.core.vars.generators.oauth2-proxy-weechat.files."env".path;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs weechatOauth2Args}";
      Restart = "always";
    };
  };

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
      extraConfig = securityHeadersConfig;
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
      extraConfig = securityHeadersConfig;
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

    ${restateDomain} = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      extraConfig = securityHeadersConfig;
      locations."/" = {
        proxyPass = "http://127.0.0.1:4181";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 50M;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    ${restateApiDomain} = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      extraConfig = securityHeadersConfig;
      locations."/".return = "404";
    };

    ${weechatDomain} = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      extraConfig = securityHeadersConfig + ''
        auth_request /oauth2/auth;
        error_page 401 = @redirectToOauth2ProxyLogin;

        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        auth_request_set $auth_cookie $upstream_http_set_cookie;
        add_header Set-Cookie $auth_cookie;
      '';
      locations = {
        "/oauth2/" = {
          proxyPass = "http://127.0.0.1:4183";
          extraConfig = ''
            auth_request off;
            proxy_set_header X-Scheme $scheme;
            proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
          '';
        };
        "= /oauth2/auth" = {
          proxyPass = "http://127.0.0.1:4183/oauth2/auth";
          extraConfig = ''
            auth_request off;
            proxy_set_header X-Scheme $scheme;
            proxy_set_header Content-Length "";
            proxy_pass_request_body off;
          '';
        };
        "@redirectToOauth2ProxyLogin" = {
          return = "307 https://${weechatDomain}/oauth2/start?rd=$scheme://$host$request_uri";
          extraConfig = ''
            auth_request off;
          '';
        };
        "^~ /weechat" = {
          proxyPass = "http://malt.n:4242";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-User $user;
            proxy_set_header X-Email $email;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
        };
        "/".root = pkgs.glowing-bear;
      };
    };
  };
}
