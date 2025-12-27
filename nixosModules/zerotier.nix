{ config, lib, ... }:
{
  options.services.zerotierone.blockRfc1918Addresses = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      If true, blocks RFC1918 addresses using systemd IPAddressDeny.
      Some cloud providers (Hetzner, Vultr) may send abuse reports
      if ZeroTier connects to private address ranges.
    '';
  };

  config = lib.mkIf config.services.zerotierone.blockRfc1918Addresses {
    systemd.services.zerotierone.serviceConfig.IPAddressDeny = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
  };
}
