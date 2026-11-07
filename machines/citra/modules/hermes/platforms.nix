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
    hermes-discord.prompts.bot-token = secret "Discord bot token for Hermes";
  };

  containers.hermes.config.services.hermes.profiles.noa.platforms = {
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
