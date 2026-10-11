{
  config,
  lib,
  pkgs,
  ...
}:
let
  pg = config.services.postgresql;
  extensions = [
    "vector"
    "pgroonga"
  ];
  # Neither extension is trusted, so the hindsight role cannot create them itself.
  # ALTER EXTENSION UPDATE keeps the catalog in step with package bumps (pgroonga requires it).
  setupSql = pkgs.writeText "hindsight-pg-setup.sql" ''
    ${lib.concatMapStringsSep "\n" (ext: ''CREATE EXTENSION IF NOT EXISTS "${ext}";'') extensions}
    ${lib.concatMapStringsSep "\n" (ext: ''ALTER EXTENSION "${ext}" UPDATE;'') extensions}
  '';
in
{
  # pgroonga's TokenBigram covers Korean without a dictionary; Hindsight selects it
  # with HINDSIGHT_API_TEXT_SEARCH_EXTENSION=pgroonga.
  services.postgresql = {
    extensions = ps: [
      ps.pgvector
      ps.pgroonga
    ];
    ensureDatabases = [ "hindsight" ];
    ensureUsers = [
      {
        name = "hindsight";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
    "${lib.getExe' pg.package "psql"} -d hindsight -v ON_ERROR_STOP=1 -f ${setupSql}"
  ];
}
