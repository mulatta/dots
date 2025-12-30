{ ... }:
{
  clan = {
    meta.name = "seungwon";

    inventory = {
      # Tags for grouping machines
      tags =
        { config, ... }:
        {
          # All NixOS machines (excludes Darwin and mulatta for now)
          nixos = builtins.filter (name: name != "rhesus" && name != "mulatta") config.all;
          # WireGuard peers (excludes controller and mulatta)
          wireguard-peers = builtins.filter (name: name != "macaca" && name != "mulatta") config.all;
        };

      machines.rhesus.machineClass = "darwin";
      machines.macaca.machineClass = "nixos";
      machines.malt.machineClass = "nixos";
      # machines.mulatta.machineClass = "nixos"; # TODO: Enable when ready

      instances = {
        # Emergency/admin access
        admin = {
          roles.default.machines.macaca = { };
          roles.default.machines.malt = { };
          roles.default.settings = {
            allowedKeys = {
              seungwon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkKJdIzvxlWcry+brNiCGLBNkxrMxFDyo1anE4xRNkL";
            };
          };
        };

        # ZeroTier VPN - macaca as controller
        # TODO: Enable after macaca is deployed (network ID generated on first run)
        # zerotier = {
        #   module.name = "zerotier";
        #   module.input = "clan-core";
        #   roles.controller.machines.macaca = { };
        #   roles.peer.tags.nixos = { };
        # };

        # WireGuard VPN - macaca as controller
        wireguard = {
          module.name = "wireguard";
          module.input = "clan-core";

          # Domain suffix for .x resolution
          roles.controller.settings.domain = "x";
          roles.peer.settings.domain = "x";

          # macaca is the controller with public endpoint
          roles.controller.machines.macaca = {
            settings = {
              endpoint = "64.176.225.253";
              port = 51820;
            };
          };

          # All other machines are peers (rhesus for now)
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
        };
      };
    };
  };
}
