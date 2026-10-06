{ ... }:
let
  domain = "trek.mulatta.io";
  port = 3010;
in
{
  # TREK speaks OIDC to Kanidm itself; nginx stays a plain reverse proxy.
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    mulatta.securityHeaders = "deny";
    extraConfig = ''
      if ($block_dotted) { return 404; }
      # Matches TREK's default BACKUP_UPLOAD_LIMIT_MB for backup restores.
      client_max_body_size 500M;
    '';

    locations."/" = {
      proxyPass = "http://malt.n:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
      '';
    };

    # Local accounts are created only by an admin (POST /api/admin/users).
    # Refuse self-registration, including invite links, so a password
    # registration toggle left on in the database cannot open sign-up.
    locations."= /api/auth/register".return = "403";
    locations."^~ /api/auth/invite/".return = "403";

    # MCP streams tool results over SSE, and TREK sends no
    # X-Accel-Buffering header, so buffering would hold events back.
    locations."/mcp" = {
      proxyPass = "http://malt.n:${toString port}";
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
