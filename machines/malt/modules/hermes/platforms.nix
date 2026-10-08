{
  config,
  pkgs,
  self,
  ...
}:
let
  vars = config.clan.core.vars.generators;
in
{
  # Slack

  # Named before other platforms existed; renaming would move the stored vars.
  clan.core.vars.generators.hermes = {
    files.slack-bot-token.secret = true;
    files.slack-app-token.secret = true;

    prompts.slack-bot-token = {
      description = "Slack bot token (xoxb-…) for the Nero app";
      type = "hidden";
    };
    prompts.slack-app-token = {
      description = "Slack app-level token (xapp-…) with connections:write for Nero";
      type = "hidden";
    };

    script = ''
      cp "$prompts/slack-bot-token" "$out/slack-bot-token"
      cp "$prompts/slack-app-token" "$out/slack-app-token"
    '';
  };

  services.hermes.settings.gateway.platforms.slack.home_channel = {
    platform = "slack";
    chat_id = "D04GJGZK4SH";
    name = "Seungwon";
  };
  services.hermes.environment.SLACK_ALLOWED_USERS = "U04GMC10NNP";
  services.hermes.credentials.slack-bot-token = {
    file = vars.hermes.files.slack-bot-token.path;
    env = "SLACK_BOT_TOKEN";
  };
  services.hermes.credentials.slack-app-token = {
    file = vars.hermes.files.slack-app-token.path;
    env = "SLACK_APP_TOKEN";
  };

}
