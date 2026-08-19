{
  lib,
  self,
  ...
}:
let
  # ZeroTier IPs are shared in Clan's multi-instance vars layout.
  tapsZerotierIP = self.lib.readVarFile null "zerotier-ip-taps-zerotier" "ip";

  # Read taps WireGuard IP for DNS server (fallback)
  tapsWireguardPrefix =
    let
      path = self + "/vars/per-machine/taps/wireguard-network-wireguard/prefix/value";
    in
    if builtins.pathExists path then lib.strings.trim (builtins.readFile path) else null;

  tapsWireguardIP = if tapsWireguardPrefix != null then "${tapsWireguardPrefix}::1" else null;
in
{
  # Use taps as primary DNS server via ZeroTier or WireGuard
  networking.nameservers = lib.mkDefault (
    lib.filter (x: x != null) [
      tapsZerotierIP
      tapsWireguardIP
      # Fallback to public DNS
      "1.1.1.1"
      "8.8.8.8"
    ]
  );

  # Route private ZeroTier suffixes to taps even when host-specific DNS
  # overrides networking.nameservers.
  systemd.network.networks."09-zerotier".networkConfig = lib.mkIf (tapsZerotierIP != null) {
    DNS = [ tapsZerotierIP ];
    Domains = [ "~z" ];
  };

  # Add search domains for unqualified internal hostnames.
  networking.search = [
    "z" # ZeroTier domain
    "x" # WireGuard domain
  ];

  # Ensure DNS resolution works with IPv6
  networking.enableIPv6 = lib.mkDefault true;
}
