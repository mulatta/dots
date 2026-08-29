{ lib, ... }:
{
  # Load Vultr's virtio-blk disk before ZFS root import.
  boot.initrd.kernelModules = [
    "virtio_pci"
    "virtio_blk"
  ];

  # Vultr VirtIO disks lack stable by-id links.
  boot.zfs.devNodes = "/dev/disk/by-partuuid";

  # Vultr recovery uses noVNC; ttyS0 is unusable.
  srvos.boot.consoles = [ "tty0" ];
  boot.loader.grub.extraConfig = lib.mkForce "";

  # Hyper-V module probing fails on Vultr.
  virtualisation.hypervGuest.enable = false;
}
