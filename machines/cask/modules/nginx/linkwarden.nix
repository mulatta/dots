{ wgLib, securityHeadersConfig, ... }:
let
  malt = wgLib.wgHost "malt";

  domain = "links.mulatta.io";
  port = 3000;
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
      client_max_body_size 100M;
    '';

    locations."/" = {
      proxyPass = "http://${malt.url}:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
      '';
    };
  };
}
