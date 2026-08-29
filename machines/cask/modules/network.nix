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

    ipv6 = {
      address = lib.mkOption {
        type = lib.types.str;
        default = "2401:c080:1c01:382:5400:6ff:fe9c:ad9d";
        description = "Stable public IPv6 address.";
      };

      prefixLength = lib.mkOption {
        type = lib.types.ints.between 0 128;
        default = 64;
        description = "Public IPv6 prefix length.";
      };

      gateway = lib.mkOption {
        type = lib.types.str;
        default = "fe80::fc00:6ff:fe9c:ad9d";
        description = "Vultr link-local IPv6 gateway.";
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
      ipv6.addresses = [
        {
          inherit (cfg.ipv6) address prefixLength;
        }
      ];
    };
    defaultGateway = {
      address = cfg.ipv4.gateway;
      interface = cfg.interface;
      source = cfg.ipv4.address;
      metric = 100;
    };
    defaultGateway6 = {
      address = cfg.ipv6.gateway;
      interface = cfg.interface;
    };
    firewall.allowedUDPPorts = [ 51820 ];
  };
}
