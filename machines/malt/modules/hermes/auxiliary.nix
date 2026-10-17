{ config, lib, ... }:
let
  gateway = "http://${config.containers.hermes.hostAddress}:${toString config.services.agentgateway.settings.gateways.default.port}";
  # API-billed models outside the ChatGPT plan, so side tasks and fallbacks keep
  # working when the main conversation hits usage_limit_reached.
  cheap = {
    provider = "agw-anthropic";
    name = "claude-haiku-5-5";
  };
  video = {
    provider = "agw-gemini";
    name = "gemini-3.1-flash-lite";
  };
in
{
  containers.hermes.config.services.hermes.profileDefaults =
    { name, ... }:
    {
      credentials.AGENTGATEWAY_TOKEN = "${name}-agentgateway-token";
      settings = {
        providers = {
          # Anthropic wire, so Hermes places cache_control markers the gateway passes through.
          agw-anthropic = {
            api = gateway;
            key_env = "AGENTGATEWAY_TOKEN";
            transport = "anthropic_messages";
            models.${cheap.name}.prompt_caching = true;
          };
          agw-gemini = {
            api = "${gateway}/v1";
            key_env = "AGENTGATEWAY_TOKEN";
            transport = "chat_completions";
          };
        };
        # A different vendor second, in case Anthropic is the one failing.
        fallback_providers =
          map
            (m: {
              inherit (m) provider;
              model = m.name;
            })
            [
              cheap
              video
            ];
      };
      # background_review and review stay on the main model: their output persists
      # and they replay the conversation on its warm cache.
      auxiliary.tasks = lib.genAttrs [
        "vision"
        "compression"
        "skills_hub"
        "approval"
        "mcp"
        "title_generation"
        "memory_query_rewrite"
        "tts_audio_tags"
        "triage_specifier"
        "kanban_decomposer"
        "profile_describer"
        "goal_judge"
        "curator"
        "monitor"
      ] (_: cheap);
    };
}
