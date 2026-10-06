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
  };
}
