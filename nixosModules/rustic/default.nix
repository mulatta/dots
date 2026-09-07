{
  config,
  lib,
  ...
}:
let
  backupPaths = lib.unique (
    lib.flatten (map (state: state.folders or [ ]) (lib.attrValues config.clan.core.state))
  );
  rootIsZfs = config.fileSystems."/".fsType == "zfs";
  excludePatterns = [
    "**/*.o"
    "**/*.pyc"
    "**/node_modules"
    "home/*/.cache"
    "home/*/.cargo"
    "home/*/.clangd"
    "home/*/.config/Ferdium/Partitions"
    "home/*/.direnv"
    "home/*/.gradle"
    "home/*/.m2"
    "home/*/.mozilla/firefox/*/storage"
    "home/*/.npm"
    "home/*/.opam"
    "home/*/Android"
    "home/*/go"
    "var/cache"
    "var/lib/containerd"
    "var/lib/containers"
    "var/lib/docker"
    "var/lib/neko"
    "var/lib/private/*/.cache"
    "var/lib/postgresql"
    "var/lib/systemd"
    "var/log"
    "var/tmp"
  ];
in
{
  imports = [
    ./options.nix
    ./config.nix
    ./zfs-snapshots.nix
  ];

  clan.core.state.system.folders = [
    "/home"
    "/var"
    "/root"
  ];

  services.rustic.backups.system = {
    sources = backupPaths;
    extraArgs = lib.concatMap (pattern: [
      "--glob"
      "!**/${lib.removePrefix "**/" pattern}"
    ]) excludePatterns;
    useZfsSnapshots = rootIsZfs;
  };
}
