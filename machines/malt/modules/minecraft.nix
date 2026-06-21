# Minecraft server reachable only over the headscale tailnet: the firewall
# opens 25565 on tailscale0 only, so there is no public or LAN-facing port.
# Vanilla (not Paper): no mod loader, smaller RCE surface. online-mode +
# whitelist are the identity gates.
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
    openFirewall = false; # opened on tailscale0 only, below
    dataDir = "/var/lib/minecraft";

    servers.survival = {
      enable = true;
      package = pkgs.vanillaServers.vanilla-1_21_11;
      serverProperties = {
        server-port = port;
        online-mode = true; # account verification + packet encryption
        white-list = true;
        enforce-whitelist = true; # enforce even if toggled at runtime
        enforce-secure-profile = true;
        spawn-protection = 0;
        motd = "malt";
      };
      whitelist = {
        # "<username>" = "<uuid>";  (UUID is the stable key)
      };
    };
  };

  # tailnet-only; never public/LAN (malt is CGNAT anyway).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ port ];

  # nix-minecraft sandboxes FS/syscall but not network egress. Block lateral
  # movement from a JVM RCE with a deny-list (default stays allow, so Mojang
  # and the loopback DNS stub keep working) covering RFC1918 LAN and the
  # wg-mesh prefix. Tailnet players are not denied. Loopback-bound services
  # stay reachable (resolver needs it) -- close with netns/container if the
  # threat grows (Paper/mods, no whitelist).
  systemd.services."minecraft-server-survival".serviceConfig = {
    NoNewPrivileges = true;
    IPAddressDeny = [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "169.254.0.0/16"
      "fe80::/10"
      "${self.lib.wgPrefix}::/64"
    ];
  };
}
