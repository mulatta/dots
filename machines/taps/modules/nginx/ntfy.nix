{
  services.nginx.virtualHosts."ntfy.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:2586";
      proxyWebsockets = true;
    };
  };
}
