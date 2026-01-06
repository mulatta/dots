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
      owner = "authelia-main";
      group = "lldap-bind";
      mode = "0440";
    };
    files."jwt-secret".secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 24 > "$out/admin-password"
      openssl rand -hex 32 > "$out/jwt-secret"
    '';
  };

  services.lldap = {
    enable = true;
    settings = {
      # Bind to all interfaces - firewall restricts access
      ldap_host = "::";
      ldap_port = 3890;
      http_host = "127.0.0.1";
      http_port = 17170;
      http_url = "https://lldap.${baseDomain}";

      ldap_base_dn = ldapBaseDn;
      ldap_user_dn = "admin";
      ldap_user_email = "admin@${baseDomain}";

      database_url = "sqlite:///var/lib/lldap/lldap.db?mode=rwc";

      # Keep built-in admin password fixed to nix-generated value
      force_ldap_user_pass_reset = "always";
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

  # Allow LDAP access from WireGuard mesh (for Nextcloud on malt)
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 3890 ];

  # Group for services that need LDAP bind access
  users.groups.lldap-bind = { };
  users.users.stalwart-mail.extraGroups = [ "lldap-bind" ];
}
