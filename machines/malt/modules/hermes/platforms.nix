{
  config,
  pkgs,
  self,
  ...
}:
let
  vars = config.clan.core.vars.generators;
  buzzOwnerPubkey = self.nixosConfigurations.cask.config.services.buzz-relay.ownerPubkey;
  buzzCli = self.inputs.buzz.packages.${pkgs.stdenv.hostPlatform.system}.buzz-cli;
  buzzRelayUrl = "https://buzz.mulatta.io";
  # Existing general channel; membership is granted by buzz-agents-sync.
  buzzChannel = "6fd9e6ce-242e-51ce-b931-7644668b87de";
  buzzAgent = config.services.buzz-agents.agents.noa;
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
    chat_id = "D0BNTAKEE84";
    name = "Seungwon";
  };
  # Deploys restart the gateway often; the notices would only add noise.
  services.hermes.settings.gateway.platforms.slack.gateway_restart_notification = false;
  # Only final answers reach chat; tool calls stay in the agent log and session history.
  services.hermes.settings.display.platforms.slack = {
    interim_assistant_messages = false;
    tool_progress = "off";
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
  services.hermes.settings.gateway.platforms.discord.gateway_restart_notification = false;
  services.hermes.settings.display.platforms.discord = {
    interim_assistant_messages = false;
    tool_progress = "off";
  };
  services.hermes.environment.DISCORD_ALLOWED_USERS = "529227359866322945";
  services.hermes.credentials.discord-bot-token = {
    file = vars.hermes-discord.files.bot-token.path;
    env = "DISCORD_BOT_TOKEN";
  };

  # Buzz

  services.buzz-agents = {
    relayUrl = buzzRelayUrl;
    ownerPubkey = buzzOwnerPubkey;
    agents.noa = {
      displayName = "noa";
      channels = [ buzzChannel ];
      before = [ "container@hermes.service" ];
    };
  };

  # Buzz is a plugin adapter: its home channel and allowlist live under `extra`.
  services.hermes.settings.gateway.platforms.buzz = {
    enabled = true;
    gateway_restart_notification = false;
    extra = {
      relay_url = buzzRelayUrl;
      cli_path = "${buzzCli}/bin/buzz";
      inherit (buzzAgent) channels;
      home_channel = builtins.head buzzAgent.channels;
      allowed_users = [ buzzOwnerPubkey ];
      allow_all_users = false;
      require_mention = true;
      transport = "auto";
      poll_interval = 10;
    };
  };
  services.hermes.settings.display.platforms.buzz = {
    interim_assistant_messages = false;
    tool_progress = "off";
  };
  services.hermes.environment.BUZZ_RELAY_URL = buzzRelayUrl;
  # Cron's `deliver: buzz` resolves the plugin's home from this variable,
  # not from `extra.home_channel`.
  services.hermes.environment.BUZZ_HOME_CHANNEL = builtins.head buzzAgent.channels;
  services.hermes.packages = [ buzzCli ];
  services.hermes.credentials.buzz-private-key = {
    file = buzzAgent.privateKeyFile;
    env = "BUZZ_PRIVATE_KEY";
  };
  services.hermes.credentials.buzz-auth-tag = {
    file = buzzAgent.authTagFile;
    env = "BUZZ_AUTH_TAG";
  };
}
