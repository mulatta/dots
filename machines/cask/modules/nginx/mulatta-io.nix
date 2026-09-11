{
  services.nginx.virtualHosts = {
    "blog.mulatta.io" = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      root = "/var/lib/gitea-publications/blog/current";
      mulatta.securityHeaders = "deny";
      extraConfig = ''
        if ($block_dotted) { return 404; }
      '';
      locations."/".tryFiles = "$uri $uri/ =404";
    };
    "mulatta.io" = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      root = "/var/lib/gitea-publications/homepage/current";
      mulatta.securityHeaders = "deny";
      extraConfig = ''
        if ($block_dotted) { return 404; }
      '';
      locations = {
        "= /cv.pdf" = {
          alias = "/var/lib/gitea-publications/cv/current/cv.pdf";
          extraConfig = ''
            default_type application/pdf;
            add_header Cache-Control "public, max-age=300" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
            add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header X-Frame-Options "DENY" always;
          '';
        };
        "/".tryFiles = "$uri $uri/ =404";
      };
    };
    "www.mulatta.io" = {
      useACMEHost = "mulatta.io";
      forceSSL = true;
      globalRedirect = "mulatta.io";
    };
  };
}
