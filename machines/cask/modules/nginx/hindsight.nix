{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "hindsight.mulatta.io";
  oauth2Port = 4183;
  env = config.clan.core.vars.generators.oauth2-proxy-hindsight.files.env.path;

  # The Hindsight control plane only supports a shared access key, so this proxy
  # is its identity gate; the API key stays on malt behind the control plane.
  oauth2Args = [
    "--provider=oidc"
    "--client-id=hindsight"
    "--oidc-issuer-url=https://idm.mulatta.io/oauth2/openid/hindsight"
    "--redirect-url=https://${domain}/oauth2/callback"
    "--scope=openid email profile"
    "--email-domain=mulatta.io"
    "--code-challenge-method=S256"
    "--insecure-oidc-allow-unverified-email=true"
    "--reverse-proxy=true"
    "--skip-provider-button=true"
    "--cookie-domain=${domain}"
    "--cookie-name=_oauth2_proxy_hindsight"
    "--cookie-secure=true"
    "--cookie-httponly=true"
    "--cookie-refresh=1h"
    "--cookie-expire=12h"
    "--upstream=http://malt.n:9121"
    "--http-address=127.0.0.1:${toString oauth2Port}"
  ];
in
{
  # Public PKCE client: the client secret is an unused placeholder.
  clan.core.vars.generators.oauth2-proxy-hindsight = {
    files.env = {
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

  systemd.services.oauth2-proxy-hindsight = {
    description = "OAuth2 Proxy for the Hindsight control plane";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "kanidm.service"
      "network-online.target"
    ];
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    restartTriggers = [ env ];
    serviceConfig = {
      User = "oauth2-proxy";
      Group = "oauth2-proxy";
      EnvironmentFile = env;
      ExecStart = "${lib.getExe config.services.oauth2-proxy.package} ${lib.escapeShellArgs oauth2Args}";
      Restart = "always";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString oauth2Port}";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 100M;
      '';
    };
  };
}
