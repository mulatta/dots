{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 4000;
  vars = config.clan.core.vars.generators;
  # Bare upstream model ids, so native paths (e.g. /v1beta/models/<id>:...) route too.
  upstreams = {
    anthropic = {
      provider = "anthropic";
      models = "claude-*";
      description = "Anthropic API key";
    };
    gemini = {
      provider = "gemini";
      models = "gemini-*";
      description = "Gemini API key from a billed AI Studio project";
    };
    openai = {
      provider = "openAI";
      models = "gpt-*";
      description = "OpenAI API key";
    };
  };
  monthly = usd: [
    {
      name = "monthly";
      limit = {
        unit = "USD";
        amount = usd;
      };
      window.rolling = "30d";
      onBudgetExceeded = "Block";
    }
  ];

  # Each client gets its own token, model scope and budget; adding one here issues a key.
  clients = {
    hermes = {
      allowedModels = [
        "claude-haiku-*"
        "gemini-*"
      ];
      budgets = monthly 10;
    };
  };
in
{
  clan.core.vars.generators = {
    agentgateway = {
      prompts = lib.mapAttrs (_: upstream: {
        inherit (upstream) description;
        type = "hidden";
      }) upstreams;
      files = lib.mapAttrs (_: _: { secret = true; }) upstreams;
      script = lib.concatMapStrings (name: ''
        cp "$prompts/${name}" "$out/${name}"
      '') (lib.attrNames upstreams);
    };
  }
  # One generator per client, so a single token can be rotated or revoked on its own.
  # Only the hash reaches the gateway config; the client gets the token itself.
  // lib.mapAttrs' (
    client: _:
    lib.nameValuePair "agentgateway-client-${client}" {
      files.token.secret = true;
      files.hash.secret = false;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.openssl
      ];
      script = ''
        openssl rand -hex 32 | tr -d '\n' > "$out/token"
        printf 'sha256:%s' "$(sha256sum < "$out/token" | cut -d' ' -f1)" > "$out/hash"
      '';
    }
  ) clients;

  services.agentgateway = {
    enable = true;
    credentials = lib.mapAttrs (name: _: vars.agentgateway.files.${name}.path) upstreams;
    settings = {
      # Attributes request-log rows to the client key's metadata.name.
      config.standardAttributes.user = "apiKey.name";
      # USD budgets only charge models with a known price; the bundled catalog predates these.
      config.modelCatalog = [
        {
          inline.providers = {
            anthropic.models.claude-haiku-5-5.rates = {
              input = "0.10";
              output = "0.50";
              cacheRead = "0.01";
              cacheWrite = "0.125";
            };
            gemini.models."gemini-3.1-flash-lite".rates = {
              input = "0.25";
              output = "1.50";
              cacheRead = "0.025";
            };
          };
        }
      ];
      gateways.default.port = port;
      llm = {
        policies.apiKey = {
          mode = "strict";
          # Each SDK sends the client key its own way: Anthropic as x-api-key, Google as
          # x-goog-api-key, OpenAI as a bearer token.
          location.expression = ''
            "x-api-key" in request.headers
              ? request.headers["x-api-key"]
              : "x-goog-api-key" in request.headers
                ? request.headers["x-goog-api-key"]
                : request.headers["authorization"].stripPrefix("Bearer ")
          '';
          keys = lib.mapAttrsToList (
            client: scope:
            scope
            // {
              keyHash = vars."agentgateway-client-${client}".files.hash.value;
              metadata.name = client;
            }
          ) clients;
        };
        models = lib.mapAttrsToList (name: upstream: {
          name = upstream.models;
          inherit (upstream) provider;
          params.apiKey.file = "/run/credentials/agentgateway.service/${name}";
        }) upstreams;
      };
    };
  };

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ port ];
}
