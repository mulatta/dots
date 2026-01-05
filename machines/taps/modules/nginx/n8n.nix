{
  self,
  config,
  ...
}:
let
  domain = "n8n.mulatta.io";
  autheliaUrl = "http://127.0.0.1:9091";

  clanLib = self.inputs.clan-core.lib;

  # Get WireGuard IPs using clan vars
  wgPrefix = config.clan.core.vars.generators.wireguard-network-wireguard.files.prefix.value;
  maltSuffix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "malt";
    generator = "wireguard-network-wireguard";
    file = "suffix";
  };
  maltWgIP = "[${wgPrefix}:${maltSuffix}]"; # IPv6 needs brackets in URLs

  # Common proxy settings
  proxyConfig = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 50M;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  '';

  # Authelia auth-request snippet (for nginx auth_request module)
  autheliaAuth = ''
    auth_request /internal/authelia/authz;
    auth_request_set $redirection_url $upstream_http_location;
    auth_request_set $user $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name $upstream_http_remote_name;
    auth_request_set $email $upstream_http_remote_email;
    error_page 401 =302 $redirection_url;

    proxy_set_header X-Email $email;
    proxy_set_header Remote-User $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Name $name;
    proxy_set_header Remote-Email $email;
  '';
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    # Authelia auth endpoint (internal) - uses auth-request endpoint for nginx
    locations."/internal/authelia/authz" = {
      proxyPass = "${autheliaUrl}/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-URI $request_uri;
      '';
    };

    # Webhook endpoints - bypass auth for external integrations
    locations."/webhook/" = {
      proxyPass = "http://${maltWgIP}:5678";
      proxyWebsockets = true;
      extraConfig = proxyConfig;
    };
    locations."/webhook-test/" = {
      proxyPass = "http://${maltWgIP}:5678";
      proxyWebsockets = true;
      extraConfig = proxyConfig;
    };

    # Main app - protected by Authelia
    locations."/" = {
      proxyPass = "http://${maltWgIP}:5678";
      proxyWebsockets = true;
      extraConfig = ''
        ${autheliaAuth}
        ${proxyConfig}
      '';
    };
  };
}
