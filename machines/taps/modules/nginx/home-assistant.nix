{
  wgLib,
  appWellKnownLocations,
  securityHeadersConfig,
  ...
}:
let
  malt = wgLib.wgHost "malt";

  domain = "home.mulatta.io";
  port = 8123;
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
    '';

    locations = appWellKnownLocations // {
      "/" = {
        proxyPass = "http://${malt.url}:${toString port}";
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
