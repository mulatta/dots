{ ... }:
{
  services.atuin = {
    enable = true;
    host = "::";
    port = 58888;
    openRegistration = false;
    openFirewall = false;
    database.createLocally = true;
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 58888 ];
}
