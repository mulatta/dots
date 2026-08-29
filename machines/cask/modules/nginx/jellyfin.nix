{ wgLib, ... }:
let
  malt = wgLib.wgHost "malt";

  domain = "video.mulatta.io";
  port = 8096;

  # The SSO-Auth plugin bootstraps Jellyfin Web localStorage through a
  # same-origin iframe. DENY breaks that flow and leaves the browser on
  # the "Logging in..." handoff page.
  securityHeadersConfig = ''
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
      client_max_body_size 20G;
    '';

    locations."/" = {
      proxyPass = "http://${malt.url}:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
