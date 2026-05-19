{ appWellKnownLocations, ... }:
{
  services.nginx.virtualHosts."relay.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    locations = appWellKnownLocations // {
      "/" = {
        proxyPass = "http://127.0.0.1:7777";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };
}
