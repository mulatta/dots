# Reverse proxy for the headscale control plane (see ../headscale.nix).
#
# headscale speaks the Tailscale "noise" (ts2021) protocol over plain
# HTTP plus long-lived streaming endpoints (/ts2021, DERP). Disable proxy
# buffering and use long timeouts so those connections are not cut short.
{
  services.nginx.virtualHosts."headscale.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8089"; # matches port in ../headscale.nix (8080 = stalwart)
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
