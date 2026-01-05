{
  services.nginx.virtualHosts."immich.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    extraConfig = ''
      # Allow large file uploads (50GB)
      client_max_body_size 50000M;

      # Extended timeouts for large uploads/downloads
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      send_timeout 600s;

      # Disable buffering for streaming
      proxy_buffering off;
      proxy_request_buffering off;
    '';

    locations."/" = {
      proxyPass = "http://malt.x:2283";
      proxyWebsockets = true;
    };
  };
}
