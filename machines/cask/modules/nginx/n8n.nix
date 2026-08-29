{ wgLib, securityHeadersConfig, ... }:
let
  malt = wgLib.wgHost "malt";

  domain = "n8n.mulatta.io";
  apiDomain = "n8n-api.mulatta.io";
in
{
  # Main domain - proxied through oauth2-proxy for SSO
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig;

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

  # API domain - direct access without SSO, for API/MCP/automation
  # Uses n8n's built-in API key authentication
  services.nginx.virtualHosts.${apiDomain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig;

    # Webhooks (inbound triggers from external SaaS like GitHub, Stripe)
    # and healthcheck are the only surfaces that legitimately need to be
    # reachable from the public internet. Everything else — REST API,
    # MCP — is internal and should be reached directly over WireGuard
    # (http://[<malt-wg-ipv6>]:5678/rest/... or /mcp/... from any peer).
    locations."~ ^/(webhook(-test)?|healthz)" = {
      proxyPass = "http://${malt.url}:5678";
      proxyWebsockets = true;
      extraConfig = ''
        # SECURITY: Prevent header injection - clear all auth headers
        proxy_set_header X-Email "";
        proxy_set_header X-Auth-Request-Email "";
        proxy_set_header X-Auth-Request-User "";
        proxy_set_header X-Access-Token "";

        client_max_body_size 50M;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };

    # Default-deny — the API domain has no web UI, so any unmatched
    # request is a scanner or a misrouted browser session.
    locations."/".return = "404";
  };
}
