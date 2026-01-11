{
  self,
  config,
  ...
}:
let
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
in
{
  services.nginx.virtualHosts."cloud.mulatta.io" = {
    forceSSL = true;
    enableACME = true;

    extraConfig = ''
      client_max_body_size 16G;
      client_body_timeout 3600s;
      proxy_connect_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_read_timeout 3600s;
    '';

    locations."/" = {
      proxyPass = "http://${maltWgIP}:80";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };

    # CalDAV/CardDAV well-known redirects
    locations."= /.well-known/carddav".return = "301 $scheme://$host/remote.php/dav";
    locations."= /.well-known/caldav".return = "301 $scheme://$host/remote.php/dav";
    locations."= /.well-known/webfinger".return = "301 $scheme://$host/index.php/.well-known/webfinger";
    locations."= /.well-known/nodeinfo".return = "301 $scheme://$host/index.php/.well-known/nodeinfo";
  };
}
