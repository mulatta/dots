{ ... }:
{
  # Miniflux credentials stay in n8n. OpenCrow reaches Miniflux through a
  # thin read-only n8n-hooks facade so the agent never holds the write-capable token.
  services.opencrow.skills.rss = ./skills/rss;
}
