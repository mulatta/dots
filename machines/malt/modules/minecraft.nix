# Minecraft server reachable only over the headscale tailnet: the firewall
# opens 25565 on tailscale0 only, so there is no public or LAN-facing port.
# Vanilla (not Paper): no mod loader, smaller RCE surface. online-mode +
# whitelist are the identity gates.
{
  self,
  pkgs,
  lib,
  ...
}:
let
  port = 25565;
  # username -> Minecraft UUID (dashed). Everyone here is whitelisted.
  users = {
    lsw1167 = "f5d061e1-c9db-47a6-8dd1-3929fd4ba98f";
    Halley76 = "352fd97d-2409-4aad-9d25-2d24b36f360a";
    _garden7 = "cfa03f09-03d7-42ad-b17e-43593c7d6213";
    GIEUK17 = "e92a2225-4879-47ac-9f6f-a598869d4248";
    Nolly_12 = "62343ba7-77f1-4949-aad7-d6aa35a79417";
    smree = "bedc1677-a297-4def-ae1b-7f9e08bbc3c3";
  };
  # Operators grouped by op-permission-level. Expand into ops.json entries.
  mkOps = lib.concatMapAttrs (
    level: names:
    lib.genAttrs names (name: {
      uuid = users.${name};
      level = lib.toInt level;
    })
  );
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
      package = pkgs.vanillaServers.vanilla-26_1_2;
      serverProperties = {
        server-port = port;
        online-mode = true; # account verification + packet encryption
        white-list = true;
        enforce-whitelist = true; # enforce even if toggled at runtime
        enforce-secure-profile = true;
        spawn-protection = 0;
        motd = "malt";
      };
      whitelist = users;
      # Operators by level. Managed here, not in-game:
      # /op at runtime is overwritten on restart.
      operators = mkOps {
        "4" = [ "lsw1167" ];
        "2" = [
          "Halley76"
          "_garden7"
          "GIEUK17"
          "Nolly_12"
          "smree"
        ];
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
