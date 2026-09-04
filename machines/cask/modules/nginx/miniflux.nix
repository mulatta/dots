{ ... }:
let
  domain = "rss.mulatta.io";
  port = 8080;
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    # Miniflux emits its own security headers; only add the shared scanner
    # filter here to avoid duplicate response headers.
    extraConfig = ''
      if ($block_dotted) { return 404; }
    '';

    locations."/" = {
      proxyPass = "http://malt.n:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
      '';
    };
  };
}
