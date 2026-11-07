{ config, pkgs, ... }:
{
  # A separate key, because initrd secrets sit unencrypted on the ESPs.
  clan.core.vars.generators.initrd-ssh = {
    files."id_ed25519".neededFor = "activation";
    files."id_ed25519.pub".secret = false;
    runtimeInputs = [ pkgs.openssh ];
    script = ''
      ssh-keygen -q -t ed25519 -N "" -C citra-initrd -f "$out/id_ed25519"
    '';
  };

  # Remote unlock: initrd sshd on the LAN, reached through malt.
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
      hostKeys = [ config.clan.core.vars.generators.initrd-ssh.files."id_ed25519".path ];
    };
  };

  boot.initrd.systemd.network.networks."10-enp10s0" = {
    matchConfig.Name = "enp10s0";
    networkConfig.DHCP = "ipv4";
  };

  # RTL8126A
  boot.initrd.availableKernelModules = [ "r8169" ];
}
