{
  lib,
  self,
  ...
}:
let
  # Helper to read clan vars
  readVarFile =
    machine: generator: file:
    let
      path = self + "/vars/per-machine/${machine}/${generator}/${file}/value";
    in
    if builtins.pathExists path then lib.strings.trim (builtins.readFile path) else null;

  # Get ZeroTier IPs for .i domain
  zerotierIPs = {
    taps = readVarFile "taps" "zerotier" "zerotier-ip";
    malt = readVarFile "malt" "zerotier" "zerotier-ip";
    pint = readVarFile "pint" "zerotier" "zerotier-ip";
    # rhesus needs vars generated first
    rhesus = readVarFile "rhesus" "zerotier" "zerotier-ip";
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

  # Generate hosts entries for a domain
  mkHostsEntries =
    ips: domain:
    lib.concatStringsSep "\n" (
      lib.filter (x: x != "") (
        lib.mapAttrsToList (name: ip: if ip != null then "${ip} ${name}.${domain} ${name}" else "") ips
      )
    );

  # taps IPs for binding
  tapsZerotierIP = zerotierIPs.taps;
  tapsWireguardIP = wgIPs.taps;

  # CoreDNS configuration - bind to VPN interfaces only to avoid conflict with systemd-resolved
  corednsConfig = ''
    # Internal ZeroTier domain (.i) - listen on ZeroTier interface
    i:53 {
      bind ${tapsZerotierIP}
      hosts {
        ${mkHostsEntries zerotierIPs "i"}
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
  # Open DNS port in firewall
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
    # ZeroTier (.i domain)
    ${mkHostsEntries zerotierIPs "i"}

    # WireGuard (.x domain)
    ${mkHostsEntries wgIPs "x"}
  '';
}
