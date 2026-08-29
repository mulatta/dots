{ securityHeadersConfig, ... }:
let
  domain = "restate.mulatta.io";
  apiDomain = "restate-api.mulatta.io";
in
{
  # Admin UI and Admin API. oauth2-proxy owns browser authentication;
  # Restate itself remains bound to WireGuard on malt.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

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

  # Runtime ingress surface. Keep closed by default until the first
  # Restate workload defines explicit public invocation paths and auth.
  services.nginx.virtualHosts.${apiDomain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig;

    locations."/".return = "404";
  };
}
