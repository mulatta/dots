{
  self,
  config,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = config.clan.core.vars.generators.wireguard-network-wireguard.files.prefix.value;
  maltSuffix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "wireguard-network-wireguard";
    file = "suffix";
  };
  maltWgIP = "[${wgPrefix}:${maltSuffix}]"; # IPv6 needs brackets in URLs

  domain = "n8n.mulatta.io";
  apiDomain = "n8n-api.mulatta.io";
in
{
  # Main domain - proxied through oauth2-proxy for SSO
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

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

    # MCP Server endpoints with SSE support
    locations."~ ^/mcp/" = {
      proxyPass = "http://${maltWgIP}:5678";
      extraConfig = ''
        # SECURITY: Prevent header injection - clear all auth headers
        proxy_set_header X-Email "";
        proxy_set_header X-Auth-Request-Email "";
        proxy_set_header X-Auth-Request-User "";
        proxy_set_header X-Access-Token "";

        # SSE (Server-Sent Events) configuration for MCP
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;

        # Long timeouts for SSE connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
      '';
    };

    # All other endpoints
    locations."/" = {
      proxyPass = "http://${maltWgIP}:5678";
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
  };
}
