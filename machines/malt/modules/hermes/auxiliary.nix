{ lib, ... }:
let
  # Side tasks stay on the ChatGPT plan but on its lightest tier, so they draw far
  # less of the quota the main conversation and Hindsight share.
  luna = effort: {
    provider = "openai-codex";
    model = "gpt-6-luna";
    reasoning_effort = effort;
  };
in
{
  # background_review and review stay on the main model: their output persists
  # and they replay the conversation on its warm cache.
  services.hermes.settings.auxiliary =
    lib.genAttrs [
      "vision"
      "compression"
      "skills_hub"
      "approval"
      "mcp"
      "title_generation"
      "tts_audio_tags"
      "triage_specifier"
      "kanban_decomposer"
      "profile_describer"
      "goal_judge"
      "curator"
      "monitor"
    ] (_: luna "low")
    // {
      # An 8-second budget leaves no room for thinking.
      memory_query_rewrite = luna "none";
    };
}
