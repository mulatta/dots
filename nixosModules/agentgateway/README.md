# agentgateway

`services.agentgateway` runs [agentgateway](https://agentgateway.dev) from
`packages/agentgateway` with a YAML config generated from `settings`. The config is
checked with `agentgateway --validate-only` at build time.

Secrets never enter `settings`. Pass them through `credentials`, which become systemd
`LoadCredential` entries, and reference them by path:

```nix
services.agentgateway = {
  enable = true;
  credentials.deepseek = config.clan.core.vars.generators.agentgateway.files.deepseek-api-key.path;
  settings.llm.models = [
    {
      name = "deepseek/*";
      provider = "openAI";
      params = {
        baseUrl = "https://api.deepseek.com/v1";
        apiKey.file = "/run/credentials/agentgateway.service/deepseek";
      };
    }
  ];
};
```

Client keys belong in `llm.policies.apiKey.keys` as `keyHash = "sha256:<hex>"`, so only
the hash is stored in the Nix store.

The module opens no firewall ports; the machine configuration does that per interface.

Defaults that machines can override:

- `config.adminAddr` is a unix socket at `/run/agentgateway/admin.sock`. The admin API has no
  authentication and can stop the gateway, so it stays off TCP; forward it with
  `ssh -L 15000:/run/agentgateway/admin.sock` to use the UI.
- `config.storage.mode` is `readOnly`: the config lives in the Nix store, so UI edits would fail
  or be lost on the next deploy.
- `config.database` is SQLite under `/var/lib/agentgateway`, which keeps API-key budget usage
  across restarts and also receives the request log. `frontendPolicies.logging.database.llm` is
  `metadata`, so the log keeps usage and cost but no prompts or completions.
- `config.statsAddr` and `config.readinessAddr` are `off`; upstream binds both on every
  interface.

`checks.x86_64-linux.nixosModule-agentgateway` covers client-key enforcement from bearer,
`x-api-key` and `x-goog-api-key` headers, upstream key injection without leaking the client key,
Anthropic `cache_control` passthrough on `/v1/messages`, native Gemini `generateContent`
routing, per-key `allowedModels`, budgets that block and persist across a restart, the
admin socket with stats and readiness closed, and a request log that names the client without
storing prompts.
