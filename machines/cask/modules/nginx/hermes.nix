{ ... }:
{
  services.nginx.virtualHosts."hermes.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";

    locations."/" = {
      proxyPass = "http://malt.n:9120";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
