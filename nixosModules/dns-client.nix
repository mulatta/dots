{ config, lib, ... }:
let
  addresses = config.networking.wireguard.interfaces.wireguard.ips or [ ];
  address = if addresses == [ ] then null else lib.head (lib.splitString "/" (lib.head addresses));
  segments = if address == null then [ ] else lib.splitString ":" address;
  prefix = lib.concatStringsSep ":" (lib.take 4 segments);
  caskWireguardIP = if address == null then null else "${prefix}::1";
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
