{
  self,
  config,
  pkgs,
  ...
}:
let
  domain = "buzz.mulatta.io";
  gen = config.clan.core.vars.generators;
in
{
  imports = [ self.inputs.buzz.nixosModules.buzz-relay ];

  # This is the operator's existing Nostr PUBLIC key, not the relay signing key.
  # Must be provisioned and tracked before evaluation.
  clan.core.vars.generators.buzz-owner = {
    files.owner-pubkey.secret = false;
    prompts.owner-pubkey.description = "Buzz owner's existing Nostr public key (64 hex characters, not npub)";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    script = ''
      tr -d '\r\n' < "$prompts/owner-pubkey" > "$out/owner-pubkey"
      if ! grep -Eq '^[0-9a-fA-F]{64}$' "$out/owner-pubkey"; then
        echo "Expected a 64-character hexadecimal Nostr public key" >&2
        exit 1
      fi
    '';
  };

  # Keep identity generation separate from external R2 prompts, so replacing
  # bucket credentials does not rotate the relay's signing or Git hook keys.
  clan.core.vars.generators.buzz-identity = {
    files.relay-private-key.secret = true;
    files.git-hook-secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/relay-private-key"
      openssl rand -hex 32 > "$out/git-hook-secret"
    '';
  };

  clan.core.vars.generators.buzz-r2 = {
    files.access-key.secret = true;
    files.secret-key.secret = true;
    prompts.access-key = {
      description = "Buzz R2 Access Key ID (buzz bucket only)";
      type = "hidden";
      persist = true;
    };
    prompts.secret-key = {
      description = "Buzz R2 Secret Access Key (buzz bucket only)";
      type = "hidden";
      persist = true;
    };
    runtimeInputs = [ pkgs.coreutils ];
    script = ''
      cat "$prompts/access-key" > "$out/access-key"
      cat "$prompts/secret-key" > "$out/secret-key"
    '';
  };

  services.buzz-relay = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 3190;
    # 8080 belongs to Stalwart. Upstream health/metrics bind all interfaces;
    # these dedicated ports stay closed in the firewall and have no proxy.
    healthPort = 8190;
    metricsPort = 9190;
    openFirewall = false;
    relayUrl = "wss://${domain}";
    ownerPubkey = gen.buzz-owner.files.owner-pubkey.value;
    requireAuthToken = true;
    requireRelayMembership = true;
    corsOrigins = [ "https://${domain}" ];
    database.createLocally = true;
    redis = {
      createLocally = true;
      port = 6381;
    };
    nginx = {
      enable = true;
      hostName = domain;
      # Reuse cask's shared certificate rather than request separate ones.
      enableACME = false;
      forceSSL = true;
    };
    secretFiles = {
      BUZZ_RELAY_PRIVATE_KEY = gen.buzz-identity.files.relay-private-key.path;
      BUZZ_GIT_HOOK_HMAC_SECRET = gen.buzz-identity.files.git-hook-secret.path;
      BUZZ_S3_ACCESS_KEY = gen.buzz-r2.files.access-key.path;
      BUZZ_S3_SECRET_KEY = gen.buzz-r2.files.secret-key.path;
    };
    media = {
      baseUrl = "https://${domain}/media";
      s3Endpoint = "https://a36871be6860124304dfb5c3b3eb8c1a.r2.cloudflarestorage.com";
      s3Bucket = "buzz";
      s3Region = "auto";
    };
    # The nginx helper defaults to wss://buzz.mulatta.io/pair.
    pairingRelay.enable = true;
  };

  services.buzz-pair-relay = {
    listenAddress = "127.0.0.1";
    port = 5190;
    openFirewall = false;
  };

  # The Buzz module owns proxy routes, including exact /pair matching. Keep
  # only cask's shared TLS/header policy and streaming upload customization.
  services.nginx.virtualHosts = {
    ${domain} = {
      useACMEHost = "mulatta.io";
      mulatta.securityHeaders = "deny";
      locations."/".extraConfig = ''
        proxy_request_buffering off;
      '';
    };
  };
}
