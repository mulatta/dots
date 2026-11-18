{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  consoleHost = "s3.mulatta.io";
  consoleUrl = "https://${consoleHost}";
  issuer = "https://idm.mulatta.io/oauth2/openid/rustfs";
  cask = self.nixosConfigurations.cask.config.networking.naru;
  rootEnv = config.clan.core.vars.generators.rustfs.files.env.path;
  oidcEnv = config.clan.core.vars.generators.kanidm-rustfs-oidc.files.env.path;

in
{
  clan.core.vars.generators = {
    rustfs = {
      files.env = {
        secret = true;
        restartUnits = [ "rustfs.service" ];
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        printf 'RUSTFS_ACCESS_KEY=%s\n' "$(openssl rand -hex 10)" > "$out/env"
        printf 'RUSTFS_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" >> "$out/env"
      '';
    };
    kanidm-rustfs-oidc = import ../../../nixosModules/rustfs/oidc-secret.nix { inherit pkgs; };
  };

  services.rustfs = {
    enable = true;
    environmentFile = rootEnv;
    settings = {
      RUSTFS_VOLUMES = "/var/lib/rustfs";
      RUSTFS_ADDRESS = "127.0.0.1:9000";
      RUSTFS_CONSOLE_ENABLE = "true";
      RUSTFS_CONSOLE_ADDRESS = "${config.networking.naru.ipv4}:9001";
      RUSTFS_BROWSER_REDIRECT_URL = consoleUrl;
      RUSTFS_IDENTITY_OPENID_ENABLE_kanidm = "on";
      RUSTFS_IDENTITY_OPENID_CONFIG_URL_kanidm = "${issuer}/.well-known/openid-configuration";
      RUSTFS_IDENTITY_OPENID_ISSUER_kanidm = issuer;
      RUSTFS_IDENTITY_OPENID_CLIENT_ID_kanidm = "rustfs";
      RUSTFS_IDENTITY_OPENID_DISPLAY_NAME_kanidm = "Kanidm";
      RUSTFS_IDENTITY_OPENID_SCOPES_kanidm = "openid,profile,email";
      RUSTFS_IDENTITY_OPENID_REDIRECT_URI_kanidm = "${consoleUrl}/rustfs/admin/v3/oidc/callback/kanidm";
      RUSTFS_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC_kanidm = "off";
      # Only the dedicated policy claim grants storage access, not ordinary groups.
      RUSTFS_IDENTITY_OPENID_CLAIM_NAME_kanidm = "rustfs_policy";
      RUSTFS_IDENTITY_OPENID_GROUPS_CLAIM_kanidm = "rustfs_policy";
      RUSTFS_IDENTITY_OPENID_ROLES_CLAIM_kanidm = "";
    };
  };

  systemd.services.rustfs = {
    restartTriggers = [
      rootEnv
      oidcEnv
    ];
    serviceConfig = {
      EnvironmentFile = lib.mkForce [
        rootEnv
        oidcEnv
      ];
      UMask = "0077";
    };
  };
  systemd.tmpfiles.settings."10-rustfs"."/var/lib/rustfs".d.mode = "0700";

  # Cask terminates public TLS; only its Naru address may reach the backend.
  networking.firewall.extraInputRules = ''
    iifname "tinc.naru" ip saddr ${cask.ipv4} tcp dport 9001 accept
  '';
}
