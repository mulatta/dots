# Remove this module and its import once the deployed package includes:
# https://github.com/NousResearch/hermes-agent/pull/101300
# https://github.com/NousResearch/hermes-agent/pull/110270
{
  pkgs,
  package,
  stateDir,
}:
let
  repair = pkgs.writeText "repair-skill-permissions.py" ''
    """Keep installed bundled copies editable until upstream fixes immutable-source sync."""

    import os
    import stat
    import sys
    from pathlib import Path


    def repair(source: Path, destination: Path) -> None:
        # Match package paths rather than chmod user-authored skills or external links.
        if destination.is_symlink() or not destination.is_dir():
            return
        for root, dirs, files in os.walk(source, followlinks=False):
            base = Path(root)
            dirs[:] = [name for name in dirs if not (base / name).is_symlink()]
            for name in [".", *files]:
                original = base / name
                if original.is_symlink():
                    continue
                relative = original.relative_to(source)
                target = destination / relative
                if any(
                    (destination / parent).is_symlink()
                    for parent in [relative, *relative.parents]
                ):
                    continue
                try:
                    # O_NOFOLLOW also rejects a final-component symlink swapped in
                    # after the path check. Operate on the descriptor, not the path.
                    fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                except FileNotFoundError:
                    continue
                try:
                    info = os.fstat(fd)
                    if info.st_uid != os.getuid():
                        continue
                    if stat.S_ISDIR(info.st_mode):
                        needed = 0o700
                    elif stat.S_ISREG(info.st_mode):
                        needed = 0o600
                    else:
                        continue
                    if info.st_mode & needed != needed:
                        os.fchmod(fd, stat.S_IMODE(info.st_mode) | needed)
                finally:
                    os.close(fd)


    if __name__ == "__main__":
        repair(Path(sys.argv[1]), Path(sys.argv[2]))
  '';
in
{
  # Periodic repair also covers skills seeded after gateway startup.
  systemd.timers.hermes-skill-permissions = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitInactiveSec = "5min";
    };
  };

  systemd.services.hermes-skill-permissions = {
    description = "Repair writable permissions on bundled Hermes skill copies";
    wantedBy = [ "multi-user.target" ];
    after = [ "hermes-gateway.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "hermes";
      Group = "hermes";
      ExecStart = "${pkgs.python3}/bin/python3 ${repair} ${package}/share/hermes/skills ${stateDir}/.hermes/skills";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "${stateDir}/.hermes" ];
    };
  };
}
