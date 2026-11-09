# ovis runs on demand from home-manager; tailnet devices reach it through this proxy only.
{ config, ... }:
let
  cert = "${config.networking.hostName}.ts.mulatta.io";
in
{
  # A service name keeps the origin, and so the pairings, if ovis moves to another host.
  mulatta.tailnetNames = [ "ovis" ];
  security.acme.certs.${cert}.group = config.services.nginx.group;

  services.nginx.enable = true;
  services.nginx.virtualHosts."ovis.ts.mulatta.io" = {
    onlySSL = true;
    useACMEHost = cert;
    locations."/" = {
      proxyPass = "http://127.0.0.1:7317";
      proxyWebsockets = true;
      # ovis checks Origin against Host and X-Forwarded-Proto, and pairs proxied clients by X-Forwarded-For.
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
}
