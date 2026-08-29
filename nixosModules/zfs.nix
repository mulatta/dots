{
  config,
  lib,
  pkgs,
  self,
  ...
}:
{
  imports = [ self.inputs.srvos.nixosModules.mixins-latest-zfs-kernel ];

  config = lib.mkIf config.boot.zfs.enabled {
    environment.systemPackages = [
      pkgs.zfs-prune-snapshots
    ];

    boot.zfs.package = pkgs.zfs_unstable;

    # Local pools cannot be imported concurrently by another machine, so
    # recovery environments must not make the next boot fail on hostId drift.
    boot.zfs.forceImportRoot = true;

    services.zfs.autoSnapshot.enable = true;
  };
}
