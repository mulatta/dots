{
  lib,
  self,
  ...
}:
let
  readVarFile = self.lib.readVarFile;

  # Get ZeroTier IPs from Clan's shared multi-instance vars
  zerotierIPs = {
    taps = readVarFile null "zerotier-ip-taps-zerotier" "ip";
    malt = readVarFile null "zerotier-ip-malt-zerotier" "ip";
    pint = readVarFile null "zerotier-ip-pint-zerotier" "ip";
    rhesus = readVarFile null "zerotier-ip-rhesus-zerotier" "ip";
  };

  # Get WireGuard IPs for .x domain
  # Controller prefix + peer suffix
  wgPrefix = readVarFile "taps" "wireguard-network-wireguard" "prefix";
  wgSuffixes = {
    taps = null; # Controller uses ::1
    malt = readVarFile "malt" "wireguard-network-wireguard" "suffix";
    pint = readVarFile "pint" "wireguard-network-wireguard" "suffix";
    rhesus = readVarFile "rhesus" "wireguard-network-wireguard" "suffix";
  };

  # Construct full WireGuard IPv6 addresses
  wgIPs = {
    taps = "${wgPrefix}::1";
    malt = if wgSuffixes.malt != null then "${wgPrefix}:${wgSuffixes.malt}" else null;
    pint = if wgSuffixes.pint != null then "${wgPrefix}:${wgSuffixes.pint}" else null;
    rhesus = if wgSuffixes.rhesus != null then "${wgPrefix}:${wgSuffixes.rhesus}" else null;
  };

  mkHostsEntries =
    ips: domain:
    lib.concatStringsSep "\n" (
      lib.filter (x: x != "") (
        lib.mapAttrsToList (name: ip: if ip != null then "${ip} ${name}.${domain} ${name}" else "") ips
      )
    );

  tapsZerotierIP = zerotierIPs.taps;
  tapsWireguardIP = wgIPs.taps;

  # CoreDNS configuration - bind to VPN interfaces only to avoid conflict with systemd-resolved
  corednsConfig = ''
    # Keep .i available while clients migrate to the ZeroTier-specific .z suffix.
    i:53 {
      bind ${tapsZerotierIP}
      hosts {
        ${mkHostsEntries zerotierIPs "i"}
        fallthrough
      }
      log
      errors
    }

    z:53 {
      bind ${tapsZerotierIP}
      hosts {
        ${mkHostsEntries zerotierIPs "z"}
        fallthrough
      }
      log
      errors
    }

    # Internal WireGuard domain (.x) - listen on WireGuard interface
    x:53 {
      bind ${tapsWireguardIP}
      hosts {
        ${mkHostsEntries wgIPs "x"}
        fallthrough
      }
      log
      errors
    }

    # Forward everything else to upstream DNS (on VPN interfaces)
    .:53 {
      bind ${tapsZerotierIP} ${tapsWireguardIP}
      forward . 1.1.1.1 8.8.8.8 {
        prefer_udp
      }
      cache 30
      log
      errors
    }
  '';
in
{
  networking.firewall = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  services.coredns = {
    enable = true;
    config = corednsConfig;
  };

  # Also add hosts entries locally for fallback
  networking.extraHosts = ''
    # ZeroTier migration domains
    ${mkHostsEntries zerotierIPs "i"}
    ${mkHostsEntries zerotierIPs "z"}

    # WireGuard (.x domain)
    ${mkHostsEntries wgIPs "x"}
  '';
}
