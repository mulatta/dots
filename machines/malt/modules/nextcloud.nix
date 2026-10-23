{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  # Kanidm OIDC settings
  kanidmDomain = "idm.mulatta.io";
  kanidmIssuer = "https://${kanidmDomain}/oauth2/openid/nextcloud";

  # cask fronts Nextcloud as the public reverse proxy.

  filesUser = "seungwon";
  filesDir = "/srv/files/${filesUser}";
  paperless = config.services.paperless;
  research = config.clan.core.vars.generators.nextcloud-research-r2.files;

  # Mount point, datadir, option pairs; options apply only on creation.
  externalMounts = [
    [
      "/Files"
      filesDir
      "enable_sharing"
      "true"
    ]
    [
      "/Inbox"
      paperless.consumptionDir
    ]
    [
      "/Documents"
      "${paperless.mediaDir}/documents/originals"
      "readonly"
      "true"
    ]
  ];
in
{
  # Not backed up to R2.
  disko.devices.zpool.zroot.datasets."files" = {
    type = "zfs_fs";
    mountpoint = "/srv/files";
    options = {
      "com.sun:auto-snapshot" = "true";
      "com.sun:auto-snapshot:frequent" = "false";
      "com.sun:auto-snapshot:hourly" = "false";
      "com.sun:auto-snapshot:monthly" = "false";
    };
  };

  clan.core.vars.generators.nextcloud = {
    files.admin-password = {
      secret = true;
      owner = "nextcloud";
    };

    runtimeInputs = [ pkgs.openssl ];

    script = ''
      openssl rand -hex 24 > "$out/admin-password"
    '';
  };

  # Read-only token scoped to the research bucket.
  clan.core.vars.generators.nextcloud-research-r2 = {
    # rustic already prompts for and validates the account ID.
    dependencies = [ "rustic-r2" ];
    files.account-id.owner = "nextcloud";
    files.access-key.owner = "nextcloud";
    files.secret-key.owner = "nextcloud";
    prompts.access-key = {
      description = "Nextcloud R2 Access Key ID (research bucket, Object Read only)";
      type = "hidden";
      persist = true;
    };
    prompts.secret-key = {
      description = "Nextcloud R2 Secret Access Key (research bucket, Object Read only)";
      type = "hidden";
      persist = true;
    };
    runtimeInputs = [ pkgs.coreutils ];
    script = ''
      cat "$in/rustic-r2/r2_account_id" > "$out/account-id"
      cat "$prompts/access-key" > "$out/access-key"
      cat "$prompts/secret-key" > "$out/secret-key"
    '';
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud35;
    hostName = "cloud.mulatta.io";

    config = {
      dbtype = "pgsql";
    };

    database.createLocally = true;
    configureRedis = true;

    settings = {
      overwriteprotocol = "https";
      trusted_proxies = [ "fdec:ca5f::/32" ];
      default_phone_region = "KR";
      maintenance_window_start = 3; # 3 AM UTC
      files_external_allow_create_new_local = true;
      # File-based logging for logreader app compatibility
      log_type = "file";
      logfile = "/var/lib/nextcloud/data/nextcloud.log";
      loglevel = 2; # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
    };

    extraApps = {
      rhwpviewer = self.inputs.rhwp-nextcloud.packages.${pkgs.stdenv.hostPlatform.system}.rhwp-viewer;
      user_oidc = pkgs.nextcloud35Packages.apps.user_oidc;
    };
    extraAppsEnable = true;
  };

  # ZFS auto-creates the dataset root-owned; reset it to the service user.
  systemd.tmpfiles.rules = [
    "Z /var/lib/nextcloud 0750 nextcloud nextcloud -"
    # chmod sets the ACL mask from the group bits; --x keeps the entries below effective.
    "d /srv/files 0710 root root -"
    "a+ /srv/files - - - - u:nextcloud:--x,u:paperless:--x,u:${filesUser}:--x"
    "d ${filesDir} 0770 nextcloud nextcloud -"
    "a+ ${filesDir} - - - - u:${filesUser}:rwx,d:u:${filesUser}:rwx,d:u:nextcloud:rwx"
  ];

  # OIDC configuration via occ commands
  # Using Kanidm public client with PKCE (no client secret needed)
  systemd.services.nextcloud-oidc-config = {
    description = "Configure Nextcloud OIDC integration with Kanidm";
    after = [
      "nextcloud-setup.service"
      "postgresql.service"
    ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ config.services.nextcloud.occ ];

    script = ''
      # Enable OIDC app
      nextcloud-occ app:enable user_oidc || true

      # user_oidc requires the clientsecret flag even for a PKCE public client,
      # so pass an empty string.
      nextcloud-occ user_oidc:provider kanidm \
        --clientid="nextcloud" \
        --clientsecret="" \
        --discoveryuri="${kanidmIssuer}/.well-known/openid-configuration" \
        --scope="openid email profile groups" \
        --unique-uid="0" \
        --mapping-uid="preferred_username" \
        --mapping-display-name="name" \
        --mapping-email="email" \
        --check-bearer="0"
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      RemainAfterExit = true;
    };
  };

  systemd.services.nextcloud-external-storage = {
    description = "Configure Nextcloud local external storage mounts";
    after = [
      "nextcloud-setup.service"
      "systemd-tmpfiles-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];

    path = [
      config.services.nextcloud.occ
      pkgs.jq
    ];

    script = ''
      nextcloud-occ app:enable files_external
      existing=$(nextcloud-occ files_external:list --output=json)

      add_mount() {
        local mount_point=$1 datadir=$2 id
        shift 2
        if jq -e --arg mp "$mount_point" 'any(.[]; .mount_point == $mp)' <<<"$existing" >/dev/null; then
          return
        fi
        id=$(nextcloud-occ files_external:create --output=json \
          --applicable-user=${filesUser} --config="datadir=$datadir" \
          "$mount_point" local null::null)
        while [ $# -gt 0 ]; do
          nextcloud-occ files_external:option "$id" "$1" "$2"
          shift 2
        done
      }

      ${lib.concatMapStrings (mount: "add_mount ${lib.escapeShellArgs mount}\n") externalMounts}

      # stdin keeps the secret out of process arguments.
      # Uploads bypass Nextcloud; rescan instead of polling R2.
      if ! jq -e 'any(.[]; .mount_point == "/Research")' <<<"$existing" >/dev/null; then
        jq -n \
          --rawfile account ${research.account-id.path} \
          --rawfile key ${research.access-key.path} \
          --rawfile secret ${research.secret-key.path} \
          '{
            mount_id: null,
            mount_point: "/Research",
            storage: "\\OCA\\Files_External\\Lib\\Storage\\AmazonS3",
            authentication_type: "amazons3::accesskey",
            configuration: {
              bucket: "research",
              hostname: "\(($account | rtrimstr("\n"))).r2.cloudflarestorage.com",
              region: "auto",
              use_ssl: true,
              use_path_style: true,
              key: ($key | rtrimstr("\n")),
              secret: ($secret | rtrimstr("\n"))
            },
            options: {
              readonly: true,
              filesystem_check_changes: 0
            },
            applicable_users: ["${filesUser}"],
            applicable_groups: []
          }' | nextcloud-occ files_external:import -
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      RemainAfterExit = true;
    };
  };

  # Paperless adds files behind Nextcloud's back.
  systemd.services.nextcloud-scan-documents = {
    description = "Index Paperless originals in Nextcloud";
    after = [ "nextcloud-external-storage.service" ];
    path = [ config.services.nextcloud.occ ];
    script = "nextcloud-occ files:scan --path=/${filesUser}/files/Documents";
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
    };
  };

  systemd.timers.nextcloud-scan-documents = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "hourly";
  };

  # Allow access from WireGuard interface
  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ 80 ];
}
