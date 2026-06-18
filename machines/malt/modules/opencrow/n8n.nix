{
  config,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  n8nApiUrl = "http://[${maltWgIP}]:5678";

  n8nHooksConfig = pkgs.writeText "n8n-hooks-config.json" (
    builtins.toJSON {
      hooks = {
        store-draft = {
          url = "${n8nApiUrl}/webhook/mail-draft-store";
          token_command = "rbw get n8n-hooks-token";
        };
        github = {
          url = "${n8nApiUrl}/webhook/context-github";
          token_command = "rbw get n8n-hooks-token";
        };
        rss = {
          url = "${n8nApiUrl}/webhook/context-rss";
          token_command = "rbw get n8n-hooks-token";
        };
        slack = {
          url = "${n8nApiUrl}/webhook/context-slack";
          token_command = "rbw get n8n-hooks-token";
        };
        vikunja = {
          url = "${n8nApiUrl}/webhook/context-vikunja";
          token_command = "rbw get n8n-hooks-token";
        };
        vikunja-task-create = {
          url = "${n8nApiUrl}/webhook/vikunja-task-create";
          token_command = "rbw get n8n-hooks-token";
        };
        linkwarden = {
          url = "${n8nApiUrl}/webhook/context-linkwarden";
          token_command = "rbw get n8n-hooks-token";
        };
        linkwarden-link-create = {
          url = "${n8nApiUrl}/webhook/linkwarden-link-create";
          token_command = "rbw get n8n-hooks-token";
        };
      };
    }
  );

  vikunjaTemplates = pkgs.runCommand "vikunja-cli-templates" { } ''
    mkdir -p "$out/share/vikunja-cli"
    cp -r ${../../../../home/.local/share/vikunja-cli/templates} "$out/share/vikunja-cli/templates"
  '';
in
{
  services.opencrow.credentialFiles."n8n-hooks-token" =
    config.clan.core.vars.generators.opencrow-n8n-hooks.files.n8n-hooks-token.path;
  services.opencrow.rbwEntries."n8n-hooks-token" = "n8n-hooks-token";

  services.opencrow.skills.github = ./skills/github;
  services.opencrow.skills.slack = ./skills/slack;
  services.opencrow.skills.vikunja = ./skills/vikunja;
  services.opencrow.skills.linkwarden = ./skills/linkwarden;
  services.opencrow.skills.buildbot-pr-check = "${
    self.inputs.skillz.packages.${system}.buildbot-pr-check
  }/share/skills/buildbot-pr-check";

  services.opencrow.environment = {
    OPENCROW_INSTANCE_ID = "noa";
  };

  services.opencrow.extraPackages = [
    self.packages.${system}.n8n-hooks
    self.inputs.skillz.packages.${system}.buildbot-pr-check
  ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/n8n-hooks 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/n8n-hooks/config.json - - - - ${n8nHooksConfig}"
    "d /var/lib/opencrow/.local/share/vikunja-cli 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.local/share/vikunja-cli/templates - - - - ${vikunjaTemplates}/share/vikunja-cli/templates"
  ];
}
