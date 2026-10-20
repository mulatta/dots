{ ... }:
{
  # Separates cask latency from malt upstream time.
  # Must precede the vhosts, which appendHttpConfig does not.
  services.nginx.commonHttpConfig = ''
    log_format cloud_timing '$remote_addr "$request" $status $body_bytes_sent '
                            'rt=$request_time uct=$upstream_connect_time '
                            'uht=$upstream_header_time urt=$upstream_response_time';
  '';

  services.nginx.virtualHosts."cloud.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    extraConfig = ''
      access_log syslog:server=unix:/dev/log,tag=nginx_cloud cloud_timing;
      client_max_body_size 16G;
      client_body_timeout 3600s;
      proxy_connect_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_read_timeout 3600s;
    '';

    locations."/" = {
      proxyPass = "http://malt.n:80";
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
