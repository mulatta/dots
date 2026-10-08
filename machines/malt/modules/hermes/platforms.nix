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
      description = "Slack bot token (xoxb-…) for the noa app";
      type = "hidden";
    };
    prompts.slack-app-token = {
      description = "Slack app-level token (xapp-…) with connections:write for noa";
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

  # Discord

  # Kept apart so rotating the bot token leaves Slack alone.
  clan.core.vars.generators.hermes-discord = {
    files.bot-token.secret = true;

    prompts.bot-token = {
      description = "Discord bot token for Hermes";
      type = "hidden";
    };

    script = ''
      cp "$prompts/bot-token" "$out/bot-token"
    '';
  };

  # No channel allowlist: every channel stays reachable; the general
  # channel only receives proactive messages.
  services.hermes.settings.gateway.platforms.discord.home_channel = {
    platform = "discord";
    chat_id = "1557515680918675469";
  };
  services.hermes.environment.DISCORD_ALLOWED_USERS = "529227359866322945";
  services.hermes.credentials.discord-bot-token = {
    file = vars.hermes-discord.files.bot-token.path;
    env = "DISCORD_BOT_TOKEN";
  };

}
