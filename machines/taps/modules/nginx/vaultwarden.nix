{
  services.nginx.virtualHosts."vaultwarden.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      client_max_body_size 128M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8222";
      proxyWebsockets = true;
    };
  };
}
