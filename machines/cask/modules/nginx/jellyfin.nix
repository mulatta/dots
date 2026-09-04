{ ... }:
let
  domain = "video.mulatta.io";
  port = 8096;

in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    # The SSO handoff bootstraps Jellyfin Web localStorage through a same-origin iframe.
    mulatta.securityHeaders = "sameorigin";
    extraConfig = ''
      if ($block_dotted) { return 404; }
      client_max_body_size 20G;
    '';

    locations."/" = {
      proxyPass = "http://malt.n:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
