{ self, lib, ... }:
let
  # taps is the public HTTPS entrypoint; no other WireGuard peer should reach
  # the user-scoped WeeChat relay directly.
  tapsWgIP = "${self.lib.wgPrefix}::1";
in
{
  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname "wireguard" ip6 saddr ${tapsWgIP} tcp dport 4242 accept
  '';
}
