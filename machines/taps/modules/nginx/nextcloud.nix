{ wgLib, ... }:
let
  malt = wgLib.wgHost "malt";
in
{
  services.nginx.virtualHosts."cloud.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    extraConfig = ''
      client_max_body_size 16G;
      client_body_timeout 3600s;
      proxy_connect_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_read_timeout 3600s;
    '';

    locations."/" = {
      proxyPass = "http://${malt.url}:80";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };

    # CalDAV/CardDAV well-known redirects
    locations."= /.well-known/carddav".return = "301 $scheme://$host/remote.php/dav";
    locations."= /.well-known/caldav".return = "301 $scheme://$host/remote.php/dav";
    locations."= /.well-known/webfinger".return = "301 $scheme://$host/index.php/.well-known/webfinger";
    locations."= /.well-known/nodeinfo".return = "301 $scheme://$host/index.php/.well-known/nodeinfo";
  };
}
