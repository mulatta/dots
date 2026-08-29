{
  wgLib,
  blockDottedPathsConfig,
  ...
}:
let
  malt = wgLib.wgHost "malt";

  domain = "rss.mulatta.io";
  port = 8080;
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    # Miniflux emits its own security headers; only add the shared scanner
    # filter here to avoid duplicate response headers.
    extraConfig = blockDottedPathsConfig;

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
