{
  clan = {
    meta = {
      name = "seungwon";
      domain = "clan";
    };

    inventory = {
      tags =
        { config, ... }:
        {
          wireguard-peers = builtins.filter (name: name != "cask") config.nixos;
        };

      machines = {
        rhesus = {
          machineClass = "darwin";
          deploy.targetHost = "root@rhesus.x";
        };
        malt = {
          machineClass = "nixos";
          deploy.targetHost = "root@malt.x";
        };
        taps.machineClass = "nixos";
        cask = {
          machineClass = "nixos";
          deploy.targetHost = "root@64.176.225.253";
        };
        pint = {
          machineClass = "nixos";
          deploy.targetHost = "root@pint.x";
        };
      };

      instances = {
        users-root = {
          module.name = "users";
          module.input = "clan-core";
          roles.default.tags.nixos = { };
          roles.default.settings = {
            user = "root";
            prompt = false;
            groups = [
              "wheel"
              "networkmanager"
            ];
          };
        };

        # WireGuard VPN - cask is the production controller
        wireguard = {
          module.name = "wireguard";
          module.input = "clan-core";

          roles.controller.settings.domain = "x";
          roles.peer.settings.domain = "x";

          roles.controller.machines.cask = {
            settings = {
              endpoint = "64.176.225.253";
              port = 51820;
            };
          };
          # Recreated taps joins as an ordinary peer. Naru remains the
          # independent recovery path instead of maintaining a second public IP.
          roles.peer.settings.controller = "cask";
          roles.peer.tags.wireguard-peers = { };
          roles.peer.machines.rhesus.settings.controller = "cask";
        };

        # Internet-reachable bootstrap identities
        internet = {
          module.name = "internet";
          module.input = "clan-core";
          roles.default.machines.cask.settings.host = "cask.i";
        };

        # SSH certificate-based authentication
        sshd = {
          module.name = "sshd";
          module.input = "clan-core";
          roles.server.tags.nixos = { };
          roles.server.settings = {
            certificate.searchDomains = [
              "i" # Internet bootstrap
              "x" # WireGuard mesh
              "n" # Tinc mesh
              "local" # mDNS/Bonjour
            ];
          };
          roles.client.tags.nixos = { };
          roles.client.settings = {
            certificate.searchDomains = [
              "i" # Internet bootstrap
              "x" # WireGuard mesh
              "n" # Tinc mesh
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
