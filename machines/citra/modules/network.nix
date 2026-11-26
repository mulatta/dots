{ lib, ... }:
{
  networking = {
    useDHCP = false;
    # Only the onboard wired port; the Wi-Fi card stays unconfigured.
    interfaces.enp10s0.useDHCP = true;

    # Extend the clan WireGuard identity with the SBEE admin network, as rhesus
    # does in darwinModules/wireguard.nix; infra registers citra's clan public key.
    wireguard.interfaces.wireguard = {
      ips = lib.mkAfter [ "10.100.0.201/32" ];
      peers = lib.mkAfter [
        {
          # eta wg-admin
          publicKey = "3fJoR3zVE9zpfKEXqvavLksOlWeFxqZd3f2fFUOkW1Y=";
          endpoint = "141.164.53.203:51820";
          allowedIPs = [ "10.100.0.1/32" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # The initrd has no machine-id, so only a MAC client ID gets it the booted system's lease.
  systemd.network.networks."40-enp10s0".dhcpV4Config.ClientIdentifier = "mac";

  # Enroll after OIDC is available; keep .x DNS and routing intact.
  # tailscale up --login-server=https://hs.mulatta.io --advertise-tags=tag:citra --accept-dns=false
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "none";
  };
}
