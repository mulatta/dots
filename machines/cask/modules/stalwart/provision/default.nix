{
  config,
  pkgs,
  ...
}:
let
  baseUrl = "http://127.0.0.1:8080";
  adminPasswordFile = config.clan.core.vars.generators.stalwart-admin.files."password".path;

  scripts = pkgs.runCommand "stalwart-provision-scripts" { } ''
    install -D -m 0444 ${./stalwart_api.py} "$out/stalwart_api.py"
    install -D -m 0555 ${./provision.py} "$out/provision.py"
  '';

  resources = pkgs.writeText "stalwart-resources.json" (builtins.toJSON (import ./resources.nix));
in
{
  # Stalwart stores domains, OAuth clients, and mailbox sharing in its own
  # database, so they are reconciled after every deployment and after any
  # database restore. Identities live in Kanidm and are never touched here.
  systemd.services.stalwart-provision = {
    description = "Reconcile declarative Stalwart control-plane resources";
    # Following stalwart.service instead of a target reconciles the control
    # plane after every start, including the restart that follows a database
    # restore, not only at deployment and boot.
    wantedBy = [ "stalwart.service" ];
    requires = [ "stalwart.service" ];
    after = [
      "kanidm.service"
      "stalwart.service"
    ];
    restartTriggers = [
      resources
      scripts
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "stalwart-mail";
      Group = "stalwart-mail";
      LoadCredential = [ "admin-password:${adminPasswordFile}" ];
      ExecStart = ''
        ${pkgs.python3}/bin/python3 ${scripts}/provision.py \
          --base-url ${baseUrl} \
          --admin-password-file %d/admin-password \
          --resources ${resources}
      '';
      TimeoutStartSec = "2min";
      UMask = "0077";
    };
  };
}
