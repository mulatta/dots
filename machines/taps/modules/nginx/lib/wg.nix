# WireGuard helper for taps nginx vhosts.
#
# Exposes `wgHost <machine>` which resolves the peer's WG IPv6 from
# clan's shared prefix + the per-machine suffix that clan publishes
# as a public value. Returns both the bare address (for config files)
# and a bracket-wrapped form ready to drop into an HTTP URL.
{ self, config }:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = config.clan.core.vars.generators.wireguard-network-wireguard.files.prefix.value;
in
{
  wgHost =
    machine:
    let
      suffix = clanLib.getPublicValue {
        flake = config.clan.core.settings.directory;
        inherit machine;
        generator = "wireguard-network-wireguard";
        file = "suffix";
      };
      ip = "${wgPrefix}:${suffix}";
    in
    {
      inherit ip;
      url = "[${ip}]"; # IPv6 must be bracketed inside a URL
    };
}
