{ ... }:
let
  domain = "fitness.mulatta.io";
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";

    locations."/" = {
      proxyPass = "http://malt.n";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 10M;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
      '';
    };
  };
}
