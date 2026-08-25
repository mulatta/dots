{
  maltNeko,
  pkgs,
  ...
}:
let
  inherit (maltNeko) network ports;

  podmanNetworkConfig = (pkgs.formats.json { }).generate "neko-podman-network.json" {
    name = network.name;
    inherit (network) id;
    driver = "bridge";
    network_interface = network.interface;
    created = "2026-08-10T00:00:00Z";
    subnets = [
      network.ipv4
      network.ipv6
    ];
    ipv6_enabled = true;
    internal = false;
    dns_enabled = false;
    ipam_options.driver = "host-local";
    options.isolate = "true";
  };
in
{
  environment.etc."containers/networks/${network.name}.json".source = podmanNetworkConfig;

  networking.firewall.interfaces.wireguard = {
    allowedTCPPorts = [
      ports.ui.host
      ports.media
    ];
    allowedUDPPorts = [ ports.media ];
  };

  networking.firewall.extraForwardRules = ''
    iifname "wireguard" oifname "${network.interface}" tcp dport { ${toString ports.ui.container}, ${toString ports.media} } accept
    iifname "wireguard" oifname "${network.interface}" udp dport ${toString ports.media} accept
    iifname "${network.interface}" oifname "wireguard" ct state established,related accept
  '';

  # Keep the browser away from malt and overlay-network services if a visited
  # page compromises Chromium. Internet egress remains available.
  networking.nftables.tables.neko-isolation = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -5; policy accept;
        iifname "${network.interface}" icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert } accept
        iifname "${network.interface}" ct state established,related accept
        iifname "${network.interface}" drop
      }

      chain forward {
        type filter hook forward priority -5; policy accept;
        iifname "${network.interface}" ct state established,related accept
        iifname "${network.interface}" ip daddr {
          10.0.0.0/8,
          100.64.0.0/10,
          127.0.0.0/8,
          169.254.0.0/16,
          172.16.0.0/12,
          192.168.0.0/16
        } drop
        iifname "${network.interface}" ip6 daddr { ::1/128, fc00::/7, fe80::/10 } drop
      }
    '';
  };

  systemd.services.podman-neko.restartTriggers = [ podmanNetworkConfig ];
}
