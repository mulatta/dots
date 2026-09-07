{
  config,
  lib,
  pkgs,
  ...
}:
let
  zfs = config.boot.zfs.package;
  zfsFileSystems = lib.mapAttrsToList (
    mountPoint: fileSystem: fileSystem // { inherit mountPoint; }
  ) (lib.filterAttrs (_: fileSystem: fileSystem.fsType == "zfs") config.fileSystems);

  pathIsWithin =
    mountPoint: path: mountPoint == "/" || path == mountPoint || lib.hasPrefix "${mountPoint}/" path;

  pathToDataset =
    path:
    let
      matches = lib.filter (
        fileSystem: pathIsWithin fileSystem.mountPoint (toString path)
      ) zfsFileSystems;
      sorted = lib.sort (
        left: right: lib.stringLength left.mountPoint > lib.stringLength right.mountPoint
      ) matches;
    in
    if sorted == [ ] then null else lib.head sorted;

  datasetsFor =
    backup:
    builtins.attrValues (
      builtins.listToAttrs (
        map (fileSystem: lib.nameValuePair fileSystem.device fileSystem) (
          lib.filter (fileSystem: fileSystem != null) (map pathToDataset backup.sources)
        )
      )
    );

  indexedDatasetsFor =
    backup: lib.imap0 (index: fileSystem: fileSystem // { inherit index; }) (datasetsFor backup);

  snapshotName = name: "rustic-${name}";
  runtimeDirectory = name: "/run/rustic-zfs/${name}";
  treeRoot = name: "${runtimeDirectory name}/tree";
  bindMountPoint = name: source: "${treeRoot name}${toString source}";
  stagingMountPoint =
    name: fileSystem: "${runtimeDirectory name}/dataset-${toString fileSystem.index}";

  snapshotSource =
    name: source:
    let
      fileSystem = pathToDataset source;
      indexedFileSystem = lib.findFirst (candidate: candidate.device == fileSystem.device) null (
        indexedDatasetsFor config.services.rustic.backups.${name}
      );
      relativePath = lib.removePrefix fileSystem.mountPoint (toString source);
      relativePathWithSlash =
        if relativePath == "" then
          ""
        else if lib.hasPrefix "/" relativePath then
          relativePath
        else
          "/${relativePath}";
    in
    if fileSystem == null || indexedFileSystem == null then
      throw "Rustic ZFS backup ${name} source ${toString source} is not on a declared ZFS filesystem"
    else
      "${stagingMountPoint name indexedFileSystem}${relativePathWithSlash}";

  resolvedSources =
    name: backup:
    if lib.length backup.sources == 1 then
      map (snapshotSource name) backup.sources
    else
      [ (treeRoot name) ];

  resolvedAsPath =
    backup:
    if backup.asPath != null then
      backup.asPath
    else if lib.length backup.sources == 1 then
      toString (lib.head backup.sources)
    else
      "/";

  prepareScript =
    name: backup:
    let
      datasets = indexedDatasetsFor backup;
      snapshot = snapshotName name;
    in
    pkgs.writeShellScript "rustic-zfs-prepare-${name}" ''
      set -euo pipefail

      ${lib.optionalString (lib.length backup.sources > 1) (
        lib.concatMapStringsSep "\n" (source: ''
          ${pkgs.util-linux}/bin/umount ${lib.escapeShellArg (bindMountPoint name source)} 2>/dev/null || true
        '') (lib.reverseList backup.sources)
      )}
      ${lib.concatMapStringsSep "\n" (fileSystem: ''
        ${pkgs.util-linux}/bin/umount ${lib.escapeShellArg (stagingMountPoint name fileSystem)} 2>/dev/null || true
      '') (lib.reverseList datasets)}
      ${lib.concatMapStringsSep "\n" (fileSystem: ''
        ${zfs}/bin/zfs destroy ${lib.escapeShellArg "${fileSystem.device}@${snapshot}"} 2>/dev/null || true
      '') datasets}

      ${zfs}/bin/zfs snapshot ${
        lib.concatMapStringsSep " " (
          fileSystem: lib.escapeShellArg "${fileSystem.device}@${snapshot}"
        ) datasets
      }

      ${lib.concatMapStringsSep "\n" (fileSystem: ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg (stagingMountPoint name fileSystem)}
        ${pkgs.util-linux}/bin/mount -t zfs -o ro ${lib.escapeShellArg "${fileSystem.device}@${snapshot}"} ${lib.escapeShellArg (stagingMountPoint name fileSystem)}
      '') datasets}
      ${lib.optionalString (lib.length backup.sources > 1) (
        lib.concatMapStringsSep "\n" (source: ''
          ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg (bindMountPoint name source)}
          ${pkgs.util-linux}/bin/mount --bind -o ro ${lib.escapeShellArg (snapshotSource name source)} ${lib.escapeShellArg (bindMountPoint name source)}
        '') backup.sources
      )}
    '';

  cleanupScript =
    name: backup:
    let
      datasets = indexedDatasetsFor backup;
      snapshot = snapshotName name;
    in
    pkgs.writeShellScript "rustic-zfs-cleanup-${name}" ''
      ${lib.optionalString (lib.length backup.sources > 1) (
        lib.concatMapStringsSep "\n" (source: ''
          ${pkgs.util-linux}/bin/umount ${lib.escapeShellArg (bindMountPoint name source)} 2>/dev/null || true
        '') (lib.reverseList backup.sources)
      )}
      ${lib.concatMapStringsSep "\n" (fileSystem: ''
        ${pkgs.util-linux}/bin/umount ${lib.escapeShellArg (stagingMountPoint name fileSystem)} 2>/dev/null || true
      '') (lib.reverseList datasets)}
      ${lib.concatMapStringsSep "\n" (fileSystem: ''
        ${zfs}/bin/zfs destroy ${lib.escapeShellArg "${fileSystem.device}@${snapshot}"} 2>/dev/null || true
      '') datasets}
    '';

  runScript =
    name: backup:
    pkgs.writeShellScript "rustic-zfs-run-${name}" ''
      set -euo pipefail

      cleanup() {
        ${cleanupScript name backup}
      }
      trap cleanup EXIT

      ${prepareScript name backup}
      "$@"
    '';

  zfsBackups = lib.filterAttrs (_: backup: backup.useZfsSnapshots) config.services.rustic.backups;
in
{
  options.services.rustic.backups = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, name, ... }:
        {
          options.useZfsSnapshots = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Read this backup from temporary read-only ZFS snapshots";
          };

          config = lib.mkIf config.useZfsSnapshots {
            _resolvedSources = resolvedSources name config;
            _resolvedAsPath = resolvedAsPath config;
            # ExecStartPre gets a separate namespace, so setup and backup must share one process tree.
            _commandPrefix = [
              "${pkgs.util-linux}/bin/unshare"
              "--mount"
              "--propagation"
              "slave"
              "${runScript name config}"
            ];
          };
        }
      )
    );
  };

  config = {
    assertions = lib.flatten (
      lib.mapAttrsToList (name: backup: [
        {
          assertion = backup.user == "root";
          message = "Rustic ZFS backup ${name} must run as root";
        }
        {
          assertion = backup.sources != [ ];
          message = "Rustic ZFS backup ${name} must have at least one source";
        }
        {
          assertion = lib.all (source: pathToDataset source != null) backup.sources;
          message = "Every source in Rustic ZFS backup ${name} must belong to a declared ZFS filesystem";
        }
      ]) zfsBackups
    );

    systemd.services = lib.mapAttrs' (
      name: backup:
      lib.nameValuePair backup.unitName {
        serviceConfig = {
          PrivateDevices = lib.mkForce false;
          RuntimeDirectory = [ "rustic-zfs/${name}" ];
          ExecStopPost = lib.mkAfter [ "${cleanupScript name backup}" ];
        };
      }
    ) zfsBackups;
  };
}
