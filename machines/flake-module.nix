{
  flake.nixosModules = {
    default = ../nixosModules/default.nix;
    bulwark-webmail = ../nixosModules/bulwark-webmail;
    restate = ../nixosModules/restate;
  };

  clan = {
    meta = {
      name = "seungwon";
      domain = "clan";
    };

    inventory = {
      tags =
        { config, ... }:
        {
          wireguard-peers = builtins.filter (name: name != "taps") (config.nixos ++ config.darwin);
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
        taps = {
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

        # ZeroTier VPN - taps as controller
        zerotier = {
          module.name = "zerotier";
          module.input = "clan-core";
          roles.controller.machines.taps = { };
          roles.moon.machines.taps.settings = {
            stableEndpoints = [ "64.176.225.253" ];
          };
          roles.peer.tags.nixos = { };
          # Darwin machines need explicit peer role (not in nixos tag)
          roles.peer.machines.rhesus = { };
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
          roles.server.settings = {
            certificate.searchDomains = [
              "i" # ZeroTier migration alias
              "z" # ZeroTier internal
              "x" # WireGuard mesh
              "local" # mDNS/Bonjour
            ];
          };
          roles.client.tags.all = { };
          roles.client.settings = {
            certificate.searchDomains = [
              "i" # ZeroTier migration alias
              "z" # ZeroTier internal
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
