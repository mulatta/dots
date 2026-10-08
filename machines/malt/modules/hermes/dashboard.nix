{
  config,
  self,
  ...
}:
let
  cask = self.nixosConfigurations.cask.config.networking.naru;
  port = 9120;
in
{
  services.hermes.settings.dashboard = {
    # Force OIDC authentication even though the backend binds loopback.
    public_url = "https://hermes.mulatta.io";
    oauth = {
      provider = "self-hosted";
      self_hosted = {
        issuer = "https://idm.mulatta.io/oauth2/openid/hermes";
        client_id = "hermes";
        scopes = "openid profile email";
      };
    };
  };

  # The dashboard stays on loopback. Only cask can reach this Naru relay.
  services.nginx.enable = true;
  services.nginx.virtualHosts."hermes.mulatta.io" = {
    listen = [
      {
        addr = config.networking.naru.ipv4;
        inherit port;
      }
      {
        addr = "[${config.networking.naru.ipv6}]";
        inherit port;
      }
    ];
    extraConfig = ''
      allow ${cask.ipv4};
      allow ${cask.ipv6};
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.hermes.dashboardPort}";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      # Cask terminates TLS. Do not replace its https scheme with this
      # private HTTP hop: Hermes needs it to issue Secure session cookies.
      extraConfig = ''
        proxy_set_header Host hermes.mulatta.io;
        proxy_set_header X-Forwarded-Host hermes.mulatta.io;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ port ];
}
