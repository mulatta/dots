{
  lib,
  self,
  ...
}:
let
  readVarFile = self.lib.readVarFile;

  wgPrefix = readVarFile "cask" "wireguard-network-wireguard" "prefix";
  wgSuffixes = {
    taps = readVarFile "taps" "wireguard-network-wireguard" "suffix";
    malt = readVarFile "malt" "wireguard-network-wireguard" "suffix";
    pint = readVarFile "pint" "wireguard-network-wireguard" "suffix";
    rhesus = readVarFile "rhesus" "wireguard-network-wireguard" "suffix";
  };

  wgIPs = {
    cask = "${wgPrefix}::1";
    taps = if wgSuffixes.taps != null then "${wgPrefix}:${wgSuffixes.taps}" else null;
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

  serviceIPs = wgIPs // {
    ca = wgIPs.cask;
  };
  caskWireguardIP = wgIPs.cask;
in
{
  networking.firewall = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  services.coredns = {
    enable = true;
    config = ''
      x:53 {
        bind ${caskWireguardIP}
        hosts {
          ${mkHostsEntries serviceIPs "x"}
          fallthrough
        }
        log
        errors
      }

      .:53 {
        bind ${caskWireguardIP}
        forward . 1.1.1.1 8.8.8.8 {
          prefer_udp
        }
        cache 30
        log
        errors
      }
    '';
  };

  networking.extraHosts = ''
    # WireGuard (.x domain)
    ${mkHostsEntries serviceIPs "x"}
  '';
}
