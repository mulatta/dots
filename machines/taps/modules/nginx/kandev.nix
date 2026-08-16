{ securityHeadersConfig, ... }:
let
  domain = "kandev.mulatta.io";
in
{
  # The edge is public, while oauth2-proxy owns application authentication and
  # Kandev itself remains reachable only through taps' WireGuard connection.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig;

    locations."/" = {
      proxyPass = "http://127.0.0.1:4184";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 100M;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
