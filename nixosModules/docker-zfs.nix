{ lib, ... }:
{
  # Docker with ZFS storage driver
  # Provides better performance and features when running on ZFS root filesystems

  # For docker
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 1;

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    storageDriver = "zfs";
    extraOptions = "--userland-proxy=false --ip-masq=true --storage-opt=zfs.fsname=zroot/root/docker";

    # not compatible with docker swarm
    liveRestore = false;
  };
}
