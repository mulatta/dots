{ pkgs, rhwp-viewer, ... }:
{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33;
    hostName = "localhost";
    config = {
      adminpassFile = toString (pkgs.writeText "adminpass" "admin");
      dbtype = "sqlite";
    };
    # Map appid -> derivation. linkFarm exposes $out at nix-apps/rhwpviewer.
    extraApps = {
      rhwpviewer = rhwp-viewer;
    };
    extraAppsEnable = true;
  };

  # Listen on all interfaces so VM port forwarding and NixOS tests can reach it.
  services.nginx.virtualHosts."localhost".listen = [
    {
      addr = "0.0.0.0";
      port = 80;
    }
  ];

  networking.firewall.allowedTCPPorts = [ 80 ];

  system.stateVersion = "25.11";
}
