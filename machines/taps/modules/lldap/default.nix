{
  config,
  pkgs,
  ...
}:
let
  baseDomain = "mulatta.io";
  ldapBaseDn = "dc=mulatta,dc=io";
in
{
  clan.core.vars.generators.lldap-secrets = {
    files."admin-password" = {
      secret = true;
      owner = "authelia-main"; # Authelia needs to read this for LDAP binding
    };
    files."jwt-secret".secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/admin-password"
      openssl rand -base64 48 | tr -d '\n' > "$out/jwt-secret"
    '';
  };

  services.lldap = {
    enable = true;
    settings = {
      ldap_host = "127.0.0.1";
      ldap_port = 3890;
      http_host = "127.0.0.1";
      http_port = 17170;
      http_url = "https://lldap.${baseDomain}";

      ldap_base_dn = ldapBaseDn;
      ldap_user_dn = "admin";
      ldap_user_email = "admin@${baseDomain}";

      database_url = "sqlite:///var/lib/lldap/lldap.db?mode=rwc";
    };
    environment = {
      LLDAP_LDAP_USER_PASS_FILE = "%d/admin-password";
      LLDAP_JWT_SECRET_FILE = "%d/jwt-secret";
    };
  };

  systemd.services.lldap.serviceConfig.LoadCredential = [
    "admin-password:${config.clan.core.vars.generators.lldap-secrets.files."admin-password".path}"
    "jwt-secret:${config.clan.core.vars.generators.lldap-secrets.files."jwt-secret".path}"
  ];

  # LLDAP Web UI is internal only - access via SSH tunnel:
  # ssh -L 17170:127.0.0.1:17170 root@taps
}
