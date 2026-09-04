{
  ...
}:
let
  domain = "tasks.mulatta.io";
  port = 3456;
in
{
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    mulatta.securityHeaders = "deny";
    extraConfig = ''
      if ($block_dotted) { return 404; }
    '';

    locations = {
      # Vikunja exposes task lists over CalDAV at /dav. Keep the exact
      # discovery endpoint open while the shared catch-all still rejects
      # unrelated /.well-known probes. CardDAV belongs to Stalwart.
      "= /.well-known/caldav".return = "301 $scheme://$host/dav";

      "/" = {
        proxyPass = "http://malt.n:${toString port}";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 50M;
          proxy_read_timeout 120s;
        '';
      };
    };
  };
}
