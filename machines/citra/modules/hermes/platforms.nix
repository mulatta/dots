{ ... }:
let
  secret = description: {
    inherit description;
    type = "hidden";
    persist = true;
  };
in
{
  clan.core.vars.generators = {
    # Named before other platforms existed; renaming would move the stored vars.
    hermes.prompts = {
      slack-bot-token = secret "Slack bot token (xoxb-…) for the noa app";
      slack-app-token = secret "Slack app-level token (xapp-…) with connections:write for noa";
    };
    # Kept apart so rotating the bot token leaves Slack alone.
    hermes-discord.prompts.bot-token = secret "Discord bot token for Hermes";
  };

  containers.hermes.config.services.hermes.profiles.noa.platforms = {
    slack = {
      enable = true;
      homeChannel = "D0BNTAKEE84";
      homeChannelName = "Seungwon";
      allowedUsers = [ "U04GMC10NNP" ];
    };

    # No channel allowlist: every channel stays reachable; the general channel
    # only receives proactive messages. Other channels keep mention-triggered
    # auto-threading.
    discord = {
      enable = true;
      homeChannel = "1557515680918675469";
      allowedUsers = [ "529227359866322945" ];
      freeResponseChannels = [
        "1558545862228058273" # noa
        "1558649413650481272" # papers
      ];
    };
  };
}
