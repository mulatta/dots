{
  config,
  pkgs,
  ...
}:
let
  # Use .x domain for WireGuard mesh access
  tapsHost = "taps.x";
  ldapBaseDn = "dc=mulatta,dc=io";
in
{
  # ZFS dataset for Nextcloud data
  disko.devices.zpool.zroot.datasets."nextcloud" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/nextcloud";
    options = {
      "com.sun:auto-snapshot" = "true";
    };
  };

  clan.core.vars.generators.nextcloud = {
    files.admin-password = {
      secret = true;
      owner = "nextcloud";
    };
    files.ldap-bind-password = {
      secret = true;
      owner = "nextcloud";
    };

    runtimeInputs = [ pkgs.openssl ];

    script = ''
      openssl rand -hex 24 > "$out/admin-password"
      openssl rand -hex 24 > "$out/ldap-bind-password"
    '';
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
    hostName = "nextcloud.mulatta.io";

    config = {
      adminuser = "admin";
      adminpassFile = config.clan.core.vars.generators.nextcloud.files.admin-password.path;
      dbtype = "pgsql";
    };

    database.createLocally = true;
    configureRedis = true;

    settings = {
      overwriteprotocol = "https";
      trusted_proxies = [ "fd28:387a:57:8f00::1" ];
      default_phone_region = "KR";
    };
  };

  # Ensure correct ownership for ZFS dataset
  systemd.tmpfiles.rules = [
    "Z /var/lib/nextcloud 0750 nextcloud nextcloud -"
  ];

  # LDAP configuration via occ commands
  # Requires creating a service account 'nextcloud' in LLDAP with the generated password
  systemd.services.nextcloud-ldap-config = {
    description = "Configure Nextcloud LDAP integration";
    after = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ config.services.nextcloud.occ ];

    script = ''
      # Enable LDAP app
      nextcloud-occ app:enable user_ldap || true

      # Check if LDAP config exists, create if not
      if ! nextcloud-occ ldap:show-config s01 &>/dev/null; then
        nextcloud-occ ldap:create-empty-config
      fi

      # Configure LDAP settings for LLDAP
      nextcloud-occ ldap:set-config s01 ldapHost "${tapsHost}"
      nextcloud-occ ldap:set-config s01 ldapPort "3890"
      nextcloud-occ ldap:set-config s01 ldapAgentName "uid=nextcloud,ou=people,${ldapBaseDn}"
      nextcloud-occ ldap:set-config s01 ldapAgentPassword "$(cat ${config.clan.core.vars.generators.nextcloud.files.ldap-bind-password.path})"
      nextcloud-occ ldap:set-config s01 ldapBase "${ldapBaseDn}"
      nextcloud-occ ldap:set-config s01 ldapBaseUsers "ou=people,${ldapBaseDn}"
      nextcloud-occ ldap:set-config s01 ldapBaseGroups "ou=groups,${ldapBaseDn}"

      # User filters - only 'users' group members can log in
      nextcloud-occ ldap:set-config s01 ldapUserFilter "(&(objectClass=person)(memberOf=cn=users,ou=groups,${ldapBaseDn}))"
      nextcloud-occ ldap:set-config s01 ldapUserFilterObjectclass "person"
      nextcloud-occ ldap:set-config s01 ldapLoginFilter "(&(objectClass=person)(memberOf=cn=users,ou=groups,${ldapBaseDn})(|(uid=%uid)(mail=%uid)))"
      nextcloud-occ ldap:set-config s01 ldapLoginFilterEmail "1"
      nextcloud-occ ldap:set-config s01 ldapLoginFilterUsername "1"

      # Group filters
      nextcloud-occ ldap:set-config s01 ldapGroupFilter "(objectClass=groupOfUniqueNames)"
      nextcloud-occ ldap:set-config s01 ldapGroupFilterObjectclass "groupOfUniqueNames"
      nextcloud-occ ldap:set-config s01 ldapGroupMemberAssocAttr "uniqueMember"

      # Attribute mappings
      nextcloud-occ ldap:set-config s01 ldapUserDisplayName "displayName"
      nextcloud-occ ldap:set-config s01 ldapEmailAttribute "mail"
      nextcloud-occ ldap:set-config s01 ldapExpertUsernameAttr "uid"

      # Enable the configuration
      nextcloud-occ ldap:set-config s01 ldapConfigurationActive "1"
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      RemainAfterExit = true;
    };
  };

  # Allow access from WireGuard interface
  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 80 ];
}
