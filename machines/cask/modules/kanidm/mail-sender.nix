{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kanidm;

  # Secrets are appended at runtime, keeping them out of the store.
  baseConfig = (pkgs.formats.toml { }).generate "kanidm-mail-sender.toml" {
    instance_display_name = "mulatta.io";
    instance_url = cfg.server.settings.origin;
    schedule = "0 * * * * * *";
    mail_from_address = "idm@mulatta.io";
    mail_reply_to_address = "seungwon@mulatta.io";
    # Relay through Stalwart like other apps, so only Stalwart holds the Resend key.
    mail_relay = "smtps://mail.mulatta.io:465";
    mail_username = "kanidm_notify";
  };

  # Root-owned output satisfies kanidm-mail-sender's config permission check.
  renderConfig = pkgs.writeShellScript "kanidm-mail-sender-config" ''
    set -euo pipefail
    target="$RUNTIME_DIRECTORY/mail-sender"
    install -m 0440 -o root -g kanidm-mail-sender /dev/null "$target"
    # jq string literals are valid TOML basic strings.
    secret() {
      printf '%s = %s\n' "$1" "$(${lib.getExe pkgs.jq} -Rs 'rtrimstr("\n")' "$CREDENTIALS_DIRECTORY/$2")"
    }
    {
      cat ${baseConfig}
      secret token token
      secret mail_password smtp-password
    } > "$target"
  '';
in
{
  # Minted once by hand (see the prompt), so no unit parses kanidm CLI output.
  clan.core.vars.generators.kanidm-mail-sender = {
    files.token.secret = true;
    prompts.token = {
      description = "Kanidm API token for mail_sender: service-account create mail_sender, group add-members idm_message_senders mail_sender, api-token generate mail_sender --readwrite";
      type = "hidden";
    };
    script = ''
      cp "$prompts/token" "$out/token"
    '';
  };

  # Set the same value as kanidm_notify's POSIX password after deploying.
  clan.core.vars.generators.kanidm-mail-sender-smtp = {
    files.password.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/password"
    '';
  };

  # kanidmd only queues outbound mail; this daemon delivers it.
  systemd.services.kanidm-mail-sender = {
    description = "Kanidm outbound mail sender";
    after = [
      "kanidm.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      User = "kanidm-mail-sender";
      Group = "kanidm-mail-sender";
      RuntimeDirectory = "kanidm-mail-sender";
      RuntimeDirectoryMode = "0750";
      LoadCredential = [
        "token:${config.clan.core.vars.generators.kanidm-mail-sender.files.token.path}"
        "smtp-password:${config.clan.core.vars.generators.kanidm-mail-sender-smtp.files.password.path}"
      ];
      ExecStartPre = "+${renderConfig}";
      ExecStart = "${cfg.package}/bin/kanidm-mail-sender -m %t/kanidm-mail-sender/mail-sender";
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
}
