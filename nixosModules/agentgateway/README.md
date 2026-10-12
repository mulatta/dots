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

`checks.x86_64-linux.agentgateway` covers client-key enforcement, upstream key
injection, and a virtual model that routes on `request.startTime`.
