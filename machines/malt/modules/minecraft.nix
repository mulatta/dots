# Minecraft server, reachable only over the headscale tailnet.
#
# Players join the tailnet (control plane on taps) and connect to
# malt.ts.mulatta.io:25565; there is no public game port. The firewall
# below opens the port solely on the tailscale interface, so even on the
# LAN the server is invisible.
#
# Vanilla (not Paper) on purpose: no plugin/mod loader means no
# third-party JAR supply chain and a far smaller remote-code-execution
# surface. Identity is handled by Mojang/Microsoft (online-mode) and the
# whitelist is the final gate on who may join. Process and network
# isolation are layered on in machines/malt/modules/minecraft-hardening
# (see the hardening commit).
{ self, pkgs, ... }:
let
  port = 25565;
in
{
  imports = [ self.inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [ self.inputs.nix-minecraft.overlay ];

  disko.devices.zpool.zroot.datasets."minecraft" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/minecraft";
    options = {
      compression = "lz4";
      recordsize = "128K";
      "com.sun:auto-snapshot" = "true";
    };
  };

  services.minecraft-servers = {
    enable = true;
    eula = true;
    # The port is opened manually below, scoped to the tailnet interface.
    openFirewall = false;
    dataDir = "/var/lib/minecraft";

    servers.survival = {
      enable = true;
      package = pkgs.vanillaServers.vanilla-1_21_11;
      serverProperties = {
        server-port = port;
        online-mode = true; # Mojang/Microsoft account verification + packet encryption
        white-list = true;
        enforce-whitelist = true; # refuse logins not on the list, even if it is toggled at runtime
        enforce-secure-profile = true;
        spawn-protection = 0;
        motd = "malt";
      };
      # nix-minecraft renders whitelist.json from this. Fill with
      # "<username>" = "<uuid>"; entries (UUID is the stable key).
      whitelist = {
      };
    };
  };

  # Only reachable through the headscale tailnet, never on a public or LAN
  # interface (malt is behind CGNAT regardless).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ port ];
}
