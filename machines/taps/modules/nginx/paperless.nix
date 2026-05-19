{ wgLib, securityHeadersConfig, ... }:
let
  malt = wgLib.wgHost "malt";

  uiDomain = "paperless.mulatta.io";
  apiDomain = "paperless-api.mulatta.io";
  port = 28981;
in
{
  # Paperless uses native OIDC against Kanidm. Keep nginx as a plain reverse
  # proxy so SSO state stays in Paperless/django-allauth instead of trusting
  # reverse-proxy auth headers.
  services.nginx.virtualHosts.${uiDomain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
      client_max_body_size 256M;
    '';

    locations."/" = {
      proxyPass = "http://${malt.url}:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  # Token-auth API surface for automation. Keep this narrower than the UI
  # vhost: Paperless REST endpoints live under /api/, including document
  # download/preview endpoints used by clients after token authentication.
  services.nginx.virtualHosts.${apiDomain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
      client_max_body_size 256M;
    '';

    locations."~ ^/api/" = {
      proxyPass = "http://${malt.url}:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        # SECURITY: prevent auth header injection from sibling SSO setups.
        proxy_set_header X-Email "";
        proxy_set_header X-Auth-Request-Email "";
        proxy_set_header X-Auth-Request-User "";
        proxy_set_header X-Access-Token "";
        proxy_set_header Remote-User "";
        proxy_set_header Remote-Email "";

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };

    locations."/".return = "404";
  };
}
