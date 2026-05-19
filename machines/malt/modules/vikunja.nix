{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  # Taps has no public suffix (it's the WG gateway), so trust the whole
  # WG /64 as reverse-proxy range. The network itself is encrypted and
  # locked to configured peers, so this is not a wider trust boundary
  # than trusting the taps peer alone.
  wgTrustedCidr = "${wgPrefix}::/64";
  # Go net.Listen / URL parsing require brackets around IPv6 hosts.
  maltWgHost = "[${maltWgIP}]";

  port = 3456;
  domain = "tasks.mulatta.io";
  kanidmDomain = "idm.mulatta.io";

  # Placeholder replaced at runtime by envsubst in preStart.
  # The secret itself lives in clan vars and is shared with kanidm on taps.
  oidcSecretPlaceholder = "$VIKUNJA_OIDC_CLIENT_SECRET";
in
{
  # ZFS dataset for Vikunja state. The service uses DynamicUser with
  # StateDirectory=vikunja, so systemd stores the real state below
  # /var/lib/private and exposes /var/lib/vikunja as a symlink.
  disko.devices.zpool.zroot.datasets."vikunja" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/private/vikunja";
    options."com.sun:auto-snapshot" = "true";
  };

  # JWT secret — per-machine, Vikunja session signing.
  clan.core.vars.generators.vikunja = {
    files.env = {
      secret = true;
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      echo "VIKUNJA_SERVICE_JWTSECRET=$(openssl rand -hex 32)" > "$out/env"
    '';
  };

  # Shared OIDC client secret — same value on taps (kanidm) and malt (vikunja).
  # Clan's `share = true` makes the value identical across both machines.
  clan.core.vars.generators.kanidm-vikunja-oidc = {
    share = true;
    files.secret = {
      secret = true;
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  services.vikunja = {
    enable = true;
    frontendScheme = "https";
    frontendHostname = domain;
    address = maltWgHost;
    inherit port;
    environmentFiles = [
      config.clan.core.vars.generators.vikunja.files.env.path
    ];
    database = {
      type = "postgres";
      host = "/run/postgresql";
      user = "vikunja";
      database = "vikunja";
    };
    settings = {
      service = {
        enableregistration = false;
        timezone = "Asia/Seoul";
        # Vikunja sits behind nginx on taps (WG-tunneled). Extract the real
        # client IP from X-Forwarded-For, but only trust that header when
        # the connection comes from the taps reverse proxy.
        ipextractionmethod = "xff";
        trustedproxies = wgTrustedCidr;
      };
      auth = {
        # OIDC-only: local accounts disabled. Emergency-admin recovery path
        # is "re-enable local briefly via a one-off nix change + vikunja
        # user create" if kanidm ever becomes unreachable.
        local.enabled = false;
        openid = {
          enabled = true;
          # Vikunja 1.0+ expects providers as an attrSet keyed by
          # provider-id (the id is used in the redirect URL
          # /auth/openid/<id> — must match kanidm originUrl).
          providers = {
            kanidm = {
              name = "Kanidm";
              authurl = "https://${kanidmDomain}/oauth2/openid/vikunja";
              clientid = "vikunja";
              clientsecret = oidcSecretPlaceholder;
              scope = "openid profile email";
            };
          };
        };
      };
    };
  };

  # Nix store config would leak the placeholder string (harmless) but more
  # importantly we need runtime rendering to inject the real secret, so
  # disable the /etc entry and point vikunja at the rendered state-dir file.
  environment.etc."vikunja/config.yaml".enable = false;

  services.postgresql.ensureDatabases = [ "vikunja" ];
  services.postgresql.ensureUsers = [
    {
      name = "vikunja";
      ensureDBOwnership = true;
    }
  ];

  systemd.services.vikunja = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];

    serviceConfig = {
      LoadCredential = [
        "oidc_secret:${config.clan.core.vars.generators.kanidm-vikunja-oidc.files.secret.path}"
      ];
      # Vikunja CLI has no --config flag; it discovers config.yaml via
      # cwd / /etc/vikunja / ~/.config/vikunja. We disabled the /etc entry
      # to avoid leaking the rendered secret into the Nix store, so instead
      # point WorkingDirectory at the state dir and render config there.
      WorkingDirectory = "/var/lib/vikunja";
    };

    preStart =
      let
        yamlTemplate =
          (pkgs.formats.yaml { }).generate "vikunja-template.yaml"
            config.services.vikunja.settings;
      in
      ''
        export VIKUNJA_OIDC_CLIENT_SECRET=$(cat "$CREDENTIALS_DIRECTORY/oidc_secret")
        ${pkgs.envsubst}/bin/envsubst \
          < ${yamlTemplate} \
          > /var/lib/vikunja/config.yaml
        chmod 0600 /var/lib/vikunja/config.yaml
      '';
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];

  # First-time admin setup (after kanidm oauth2.vikunja is provisioned and
  # user has logged in via OIDC at least once):
  #
  #   ssh malt.x sudo systemd-run --pipe --wait \
  #     --property=DynamicUser=true \
  #     --property=StateDirectory=vikunja \
  #     --property=User=vikunja \
  #     --property=WorkingDirectory=/var/lib/vikunja \
  #     /run/current-system/sw/bin/vikunja user list
  #
  # Then promote the OIDC-provisioned user by id:
  #   ... vikunja user promote <id>
  #
  # If an old local user exists from the WG-only test phase, drop it:
  #   ... vikunja user delete -c -n <id>
}
