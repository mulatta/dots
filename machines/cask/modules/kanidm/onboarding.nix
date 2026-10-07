{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kanidm;
  inherit (cfg.provision) groups;

  membersOf =
    group:
    lib.unique (
      lib.concatMap (m: if groups ? ${m} then membersOf m else [ m ]) groups.${group}.members
    );

  people = membersOf "people";

  # Mailbox access must not escalate to admin, so admins never get reset links.
  onboarded = lib.subtractLists (membersOf "admins") people;
in
{
  # Minted once by hand (see the prompt), so no unit parses kanidm CLI output.
  clan.core.vars.generators.kanidm-onboarding = {
    files.token.secret = true;
    prompts.token = {
      description = "Kanidm API token for onboarding: service-account create onboarding, group add-members idm_service_desk onboarding, api-token generate onboarding --readwrite";
      type = "hidden";
    };
    script = ''
      cp "$prompts/token" "$out/token"
    '';
  };

  # One reset mail per person; markers prevent resends. Self-service
  # recovery stays off because it cannot exclude admins.
  systemd.services.kanidm-onboarding = {
    description = "Mail initial Kanidm credential reset links to people";
    after = [ "kanidm.service" ];
    requires = [ "kanidm.service" ];
    # Re-runs after each kanidm start, i.e. after provisioning adds a person.
    wantedBy = [ "kanidm.service" ];
    path = [ pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "kanidm-onboarding";
      LoadCredential = "token:${config.clan.core.vars.generators.kanidm-onboarding.files.token.path}";
    };
    script = ''
      set -euo pipefail
      failed=0
      for name in ${lib.escapeShellArgs onboarded}; do
        marker="$STATE_DIRECTORY/$name"
        [ -e "$marker" ] && continue
        # 86400 s is Kanidm's max TTL; the header file keeps the token out of argv.
        if curl --silent --show-error --fail-with-body \
          -H @<(printf 'Authorization: Bearer %s\n' "$(< "$CREDENTIALS_DIRECTORY/token")") \
          -H 'Content-Type: application/json' \
          --data '{"ttl": 86400}' \
          "${cfg.server.settings.origin}/v1/person/$name/_credential/_update_intent_send"; then
          touch "$marker"
          echo "Queued credential reset mail for $name"
        else
          echo "Failed to queue credential reset mail for $name" >&2
          failed=1
        fi
      done
      exit "$failed"
    '';
  };
}
