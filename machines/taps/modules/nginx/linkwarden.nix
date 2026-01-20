{
  services.nginx.virtualHosts."links.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    extraConfig = ''
      # Allow reasonably large file uploads for screenshots/archives
      client_max_body_size 100M;

      # Extended timeouts for archive processing
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
    '';

    # Direct proxy to linkwarden (SSO handled by linkwarden itself)
    locations."/" = {
      proxyPass = "http://malt.x:3000";
      proxyWebsockets = true;
    };
  };
}
