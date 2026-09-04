{
  config,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  n8nApiUrl = "http://malt.n:5678";

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

in
{
  services.opencrow.credentialFiles."n8n-hooks-token" =
    config.clan.core.vars.generators.opencrow-n8n-hooks.files.n8n-hooks-token.path;
  services.opencrow.rbwEntries."n8n-hooks-token" = "n8n-hooks-token";

  services.opencrow.skills.github = ./skills/github;
  services.opencrow.skills.slack = ./skills/slack;
  services.opencrow.skills.linkwarden = ./skills/linkwarden;
  services.opencrow.skills.nixbot-cli = "${
    self.inputs.nixbot.packages.${system}.nixbot-cli
  }/share/skills/nixbot-cli";

  services.opencrow.environment = {
    OPENCROW_INSTANCE_ID = "noa";
  };

  services.opencrow.extraPackages = [
    self.packages.${system}.n8n-hooks
    self.inputs.nixbot.packages.${system}.nixbot-cli
  ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/n8n-hooks 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/n8n-hooks/config.json - - - - ${n8nHooksConfig}"
  ];
}
