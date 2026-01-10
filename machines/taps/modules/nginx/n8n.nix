{
  ...
}:
let
  domain = "n8n.mulatta.io";
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:4180";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 50M;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
