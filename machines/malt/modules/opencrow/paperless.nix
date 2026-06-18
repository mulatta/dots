{
  config,
  pkgs,
  self,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  paperlessUrl = "http://[${maltWgIP}]:${toString config.services.paperless.port}";
  paperlessCliConfig = (pkgs.formats.json { }).generate "paperless-cli-config.json" {
    url = paperlessUrl;
    base_url = paperlessUrl;
    token_command = "rbw get paperless-api-token";
  };
in
{
  clan.core.vars.generators.opencrow-paperless = {
    files.paperless-api-token.secret = true;

    prompts.paperless-api-token = {
      description = "Paperless-ngx API token for OpenCrow";
      type = "hidden";
    };

    script = ''
      cp "$prompts/paperless-api-token" "$out/paperless-api-token"
    '';
  };

  services.opencrow.credentialFiles."paperless-api-token" =
    config.clan.core.vars.generators.opencrow-paperless.files.paperless-api-token.path;

  services.opencrow.rbwEntries."paperless-api-token" = "paperless-api-token";

  services.opencrow.environment.PAPERLESS_URL = paperlessUrl;

  services.opencrow.skills.paperless = ./skills/paperless;

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/paperless-cli 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/paperless-cli/config.json - - - - ${paperlessCliConfig}"
  ];
}
