{ securityHeadersConfig, ... }:
let
  domain = "zotero.mulatta.io";
  # zhost serves sync/reads directly; only enrollment is gated.
  zhost = "http://127.0.0.1:8189";
  oauth2 = "http://127.0.0.1:4182";
  # PDFs are large and stream through zhost on upload; don't buffer or cap small.
  uploadConfig = ''
    client_max_body_size 512M;
    proxy_request_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  '';
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig;

    locations = {
      # Enrollment: the browser must authenticate against kanidm first, so the
      # whole /login flow and the oauth2-proxy's own endpoints go to the proxy,
      # whose upstream is zhost (it forwards X-Auth-Request-Email after auth).
      "/login" = {
        proxyPass = oauth2;
        proxyWebsockets = true;
      };
      "/oauth2/" = {
        proxyPass = oauth2;
      };

      # Everything else (the Zotero sync API + presigned-download redirects) is
      # public; reachability is not the gate, the API key is.
      "/" = {
        proxyPass = zhost;
        proxyWebsockets = true;
        extraConfig = uploadConfig;
      };
    };
  };
}
