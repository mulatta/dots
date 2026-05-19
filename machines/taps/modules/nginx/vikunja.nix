{
  wgLib,
  appWellKnownLocations,
  securityHeadersConfig,
  ...
}:
let
  malt = wgLib.wgHost "malt";

  domain = "tasks.mulatta.io";
  port = 3456;
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
    '';

    locations = appWellKnownLocations // {
      # Vikunja exposes task lists over CalDAV at /dav. Keep the exact
      # discovery endpoint open while the shared catch-all still rejects
      # unrelated /.well-known probes. CardDAV belongs to Stalwart.
      "= /.well-known/caldav".return = "301 $scheme://$host/dav";

      "/" = {
        proxyPass = "http://${malt.url}:${toString port}";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 50M;
          proxy_read_timeout 120s;
        '';
      };
    };
  };
}
