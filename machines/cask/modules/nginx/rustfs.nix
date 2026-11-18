{ self, ... }:
let
  citra = self.nixosConfigurations.citra.config.networking.naru;
in
{
  # Preserve the signed authority, including an explicit HTTPS port, while
  # allowing only this service's public hostname through to RustFS.
  services.nginx.appendHttpConfig = ''
    map $http_host $rustfs_host {
      default "";
      s3.mulatta.io s3.mulatta.io;
      s3.mulatta.io:443 s3.mulatta.io:443;
    }
  '';
  services.nginx.virtualHosts."s3.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    extraConfig = ''
      if ($rustfs_host = "") { return 400; }
      client_max_body_size 0;
    '';
    # A URI-less proxyPass preserves signed S3 paths, including repeated slashes.
    locations."/" = {
      proxyPass = "http://${citra.ipv4}:9001";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host $rustfs_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
