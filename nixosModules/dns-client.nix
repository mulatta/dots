{
  lib,
  self,
  ...
}:
let
  # Read cask WireGuard IP for DNS service access.
  caskWireguardPrefix = self.lib.readVarFile "cask" "wireguard-network-wireguard" "prefix";

  caskWireguardIP = if caskWireguardPrefix != null then "${caskWireguardPrefix}::1" else null;
in
{
  networking.nameservers = lib.mkDefault (
    lib.filter (x: x != null) [
      caskWireguardIP
      "1.1.1.1"
      "8.8.8.8"
    ]
  );

  networking.search = [ "x" ];

  networking.enableIPv6 = lib.mkDefault true;
}
