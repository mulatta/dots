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

  # Get taps ZeroTier IP for DNS
  tapsZerotierIP = readVarFile "taps" "zerotier" "zerotier-ip";

  # Read taps WireGuard IP for DNS server
  tapsWireguardPrefix = readVarFile "taps" "wireguard-network-wireguard" "prefix";
  tapsWireguardIP = if tapsWireguardPrefix != null then "${tapsWireguardPrefix}::1" else null;
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

  # Note: Darwin doesn't have networking.hostFiles
  # Host resolution for .i and .x domains is handled by taps CoreDNS
}
