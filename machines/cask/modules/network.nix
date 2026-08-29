{ config, lib, ... }:
let
  cfg = config.networking.cask;
in
{
  options.networking.cask = {
    interface = lib.mkOption {
      type = lib.types.str;
      default = "enp1s0";
      description = "Public network interface.";
    };

    ipv4 = {
      address = lib.mkOption {
        type = lib.types.str;
        default = "64.176.225.253";
        description = "Reserved public IPv4 address.";
      };

      prefixLength = lib.mkOption {
        type = lib.types.ints.between 0 32;
        default = 32;
        description = "Reserved public IPv4 prefix length.";
      };

      gateway = lib.mkOption {
        type = lib.types.str;
        default = "158.247.204.1";
        description = "Vultr public IPv4 gateway.";
      };
    };
  };

  config.networking = {
    interfaces.${cfg.interface} = {
      useDHCP = true;
      ipv4.addresses = [
        {
          inherit (cfg.ipv4) address prefixLength;
        }
      ];
    };
    defaultGateway = {
      address = cfg.ipv4.gateway;
      interface = cfg.interface;
      source = cfg.ipv4.address;
      metric = 100;
    };
    firewall.allowedUDPPorts = [ 51820 ];
  };
}
