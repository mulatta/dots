{
  config,
  pkgs,
  ...
}:
let
  port = 3307;
  credentials = config.clan.core.vars.generators.dolt.files;
in
{
  clan.core.vars.generators.dolt = {
    files.admin-password = {
      secret = true;
      owner = "dolt";
    };
    files.client-password = {
      secret = true;
      owner = "dolt";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/admin-password"
      openssl rand -hex 32 > "$out/client-password"
    '';
  };

  services.dolt = {
    enable = true;
    settings = {
      behavior.auto_gc_behavior = {
        enable = true;
        archive_level = 1;
      };
      # Go treats the IPv4 wildcard as dual-stack; the firewall limits it to naru.
      listener = {
        host = "0.0.0.0";
        inherit port;
      };
    };
    ensureUsers = [
      {
        name = "admin";
        host = "localhost";
        passwordFile = credentials.admin-password.path;
        privileges = "ALL PRIVILEGES";
        grantOption = true;
      }
      # Beads clients create one database per project, so the grant spans all
      # databases but excludes user and grant management.
      {
        name = "beads";
        passwordFile = credentials.client-password.path;
        privileges = "SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, REFERENCES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, TRIGGER, EVENT";
      }
    ];
  };

  # Tinc already encrypts naru traffic, so the server skips TLS.
  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ port ];
}
