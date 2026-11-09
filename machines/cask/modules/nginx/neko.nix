{ ... }:
{
  # UI/signalling only. Media stays on Naru; Chromium CDP stays off the public proxy.
  services.nginx.virtualHosts."neko.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";
    extraConfig = ''
      if ($block_dotted) { return 404; }
    '';
    locations."/" = {
      proxyPass = "http://citra.n:8082";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
      '';
    };
  };
}
