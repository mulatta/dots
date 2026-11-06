{ ... }:
let
  domain = "nixbot.mulatta.io";
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://citra.n";
      extraConfig = ''
        # GitHub caps webhook payloads at 25 MB.
        client_max_body_size 25m;
        # SSE log streams.
        proxy_buffering off;
        proxy_read_timeout 3600s;
      '';
    };
  };
}
