{
  clan = {
    meta.name = "seungwon";

    inventory = {
      # Tags for grouping machines
      tags =
        { config, ... }:
        {
          # All NixOS machines (excludes Darwin)
          nixos = builtins.filter (name: name != "rhesus") config.all;
          wireguard-peers = builtins.filter (name: name != "taps") config.all;
        };

      machines.rhesus.machineClass = "darwin";
      machines.malt.machineClass = "nixos";
      machines.taps.machineClass = "nixos";
      machines.pint.machineClass = "nixos";

      instances = {
        admin = {
          roles.default.machines.malt = { };
          roles.default.machines.taps = { };
          roles.default.machines.pint = { };
          roles.default.settings = {
            allowedKeys = {
              seungwon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkKJdIzvxlWcry+brNiCGLBNkxrMxFDyo1anE4xRNkL";
            };
          };
        };

        # WireGuard VPN - taps as controller
        wireguard = {
          module.name = "wireguard";
          module.input = "clan-core";

          # Domain suffix for .x resolution
          roles.controller.settings.domain = "x";
          roles.peer.settings.domain = "x";

          # taps is the controller with public endpoint
          roles.controller.machines.taps = {
            settings = {
              endpoint = "64.176.225.253";
              port = 51820;
            };
          };
          roles.peer.tags.wireguard-peers = { };
        };

        # SSH certificate-based authentication
        sshd = {
          module.name = "sshd";
          module.input = "clan-core";
          roles.server.tags.nixos = { };
          roles.client.tags.all = { };
          roles.client.settings = {
            certificate.searchDomains = [
              "i" # ZeroTier internal
              "x" # WireGuard mesh
              "local" # mDNS/Bonjour
            ];
          };
          roles.client.extraModules = [
            ../nixosModules/ssh.nix
          ];
        };
      };
    };
  };
}
