{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.boot.zfs.enabled {
    clan.core.vars.generators.hostId = {
      files.id.secret = false;
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n' > "$out"/id
      '';
    };

    networking.hostId = builtins.readFile config.clan.core.vars.generators.hostId.files.id.path;
    boot.zfs.forceImportRoot = false;
  };
}
