{
  ...
}:
let
  securityHeadersConfig = ''
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';
  domain = "home.mulatta.io";
  port = 8123;
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
    '';

    locations = {
      "/" = {
        proxyPass = "http://malt.n:${toString port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };
  };
}
