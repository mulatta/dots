{ ... }:
let
  domain = "links.mulatta.io";
  port = 3000;
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    mulatta.securityHeaders = "deny";
    extraConfig = ''
      if ($block_dotted) { return 404; }
      client_max_body_size 100M;
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
