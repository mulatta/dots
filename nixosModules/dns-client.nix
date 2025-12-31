{
  lib,
  self,
  ...
}:
let
  # Read taps ZeroTier IP for DNS server
  tapsZerotierIP =
    let
      path = self + "/vars/per-machine/taps/zerotier/zerotier-ip/value";
    in
    if builtins.pathExists path then lib.strings.trim (builtins.readFile path) else null;

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

  # Add search domains for internal resolution
  networking.search = [
    "i" # ZeroTier domain
    "x" # WireGuard domain
  ];

  # Ensure DNS resolution works with IPv6
  networking.enableIPv6 = lib.mkDefault true;
}
