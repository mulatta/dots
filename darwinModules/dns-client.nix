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
    rhesus = readVarFile "rhesus" "zerotier" "zerotier-ip";
  };

  # Get WireGuard IPs for .x domain
  wgPrefix = readVarFile "taps" "wireguard-network-wireguard" "prefix";
  wgSuffixes = {
    taps = null; # Controller uses ::1
    malt = readVarFile "malt" "wireguard-network-wireguard" "suffix";
    pint = readVarFile "pint" "wireguard-network-wireguard" "suffix";
    rhesus = readVarFile "rhesus" "wireguard-network-wireguard" "suffix";
  };

  wgIPs = {
    taps = if wgPrefix != null then "${wgPrefix}::1" else null;
    malt =
      if wgPrefix != null && wgSuffixes.malt != null then "${wgPrefix}:${wgSuffixes.malt}" else null;
    pint =
      if wgPrefix != null && wgSuffixes.pint != null then "${wgPrefix}:${wgSuffixes.pint}" else null;
    rhesus =
      if wgPrefix != null && wgSuffixes.rhesus != null then "${wgPrefix}:${wgSuffixes.rhesus}" else null;
  };

  # Generate hosts entries
  mkHostsEntries =
    ips: domain:
    lib.concatStringsSep "\n" (
      lib.filter (x: x != "") (
        lib.mapAttrsToList (name: ip: if ip != null then "${ip} ${name}.${domain}" else "") ips
      )
    );

  tapsZerotierIP = zerotierIPs.taps;
  tapsWireguardIP = wgIPs.taps;
in
{
  # macOS resolver configuration for .i and .x domains
  # DNS queries for these TLDs are sent to taps CoreDNS
  environment.etc."resolver/i" = lib.mkIf (tapsZerotierIP != null) {
    text = ''
      nameserver ${tapsZerotierIP}
    '';
  };

  environment.etc."resolver/x" = lib.mkIf (tapsWireguardIP != null) {
    text = ''
      nameserver ${tapsWireguardIP}
    '';
  };

  # Local hosts entries for fallback (when VPN DNS isn't reachable)
  # Append to /etc/hosts via activation script
  system.activationScripts.postActivation.text =
    let
      zerotierHostsContent = mkHostsEntries zerotierIPs "i";
      wireguardHostsContent = mkHostsEntries wgIPs "x";
    in
    lib.mkAfter ''
            echo "Updating /etc/hosts with VPN entries..."

            # Remove old VPN entries
            sed -i "" "/# BEGIN ZEROTIER HOSTS/,/# END ZEROTIER HOSTS/d" /etc/hosts 2>/dev/null || true
            sed -i "" "/# BEGIN WIREGUARD HOSTS/,/# END WIREGUARD HOSTS/d" /etc/hosts 2>/dev/null || true

            # Add ZeroTier hosts
            cat >> /etc/hosts << 'EOFZT'

      # BEGIN ZEROTIER HOSTS
      ${zerotierHostsContent}
      # END ZEROTIER HOSTS
      EOFZT

            # Add WireGuard hosts
            cat >> /etc/hosts << 'EOFWG'

      # BEGIN WIREGUARD HOSTS
      ${wireguardHostsContent}
      # END WIREGUARD HOSTS
      EOFWG
    '';
}
