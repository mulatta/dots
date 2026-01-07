{ pkgs, ... }:
{
  services.nginx.virtualHosts."rad.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    # Serve radicle-explorer static files
    root = "${pkgs.radicle-explorer}";

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
      extraConfig = ''
        add_header Cache-Control "public, max-age=3600";
      '';
    };

    # Proxy API requests to radicle-httpd
    locations."/api/" = {
      proxyPass = "http://127.0.0.1:8889";
      proxyWebsockets = true;
    };
  };
}
