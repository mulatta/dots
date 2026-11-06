{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  domain = "nixbot.mulatta.io";
  gen = config.clan.core.vars.generators;
  inherit (config.networking) naru;
in
{
  imports = [ self.inputs.nixbot.nixosModules.nixbot ];

  # nixbot does not push the webhook secret; copy it into the App.
  clan.core.vars.generators.nixbot-github = {
    files.app-id.secret = false;
    files.oauth-id.secret = false;
    files.private-key.owner = "nixbot";
    files.oauth-secret.owner = "nixbot";
    files.webhook-secret.owner = "nixbot";
    prompts.app-id.description = "GitHub App ID for nixbot.mulatta.io";
    prompts.oauth-id.description = "GitHub App client ID for nixbot.mulatta.io";
    prompts.private-key = {
      description = "GitHub App private key (PEM) for nixbot.mulatta.io";
      type = "multiline-hidden";
      persist = true;
    };
    prompts.oauth-secret = {
      description = "GitHub App client secret for nixbot.mulatta.io";
      type = "hidden";
      persist = true;
    };
    script = ''
      tr -d '\r\n' < "$prompts/app-id" > "$out/app-id"
      tr -d '\r\n' < "$prompts/oauth-id" > "$out/oauth-id"
      cp "$prompts/private-key" "$out/private-key"
      cp "$prompts/oauth-secret" "$out/oauth-secret"
      ${pkgs.xkcdpass}/bin/xkcdpass -n 6 -d - > "$out/webhook-secret"
    '';
  };

  # Copy of cask's niks3/api-token.
  clan.core.vars.generators.nixbot-niks3 = {
    files.token.owner = "nixbot";
    prompts.token = {
      description = "niks3.mulatta.io API token (cask niks3/api-token)";
      type = "hidden";
      persist = true;
    };
    script = ''
      cp "$prompts/token" "$out/token"
    '';
  };

  services.nixbot = {
    enable = true;
    inherit domain;
    # TLS ends on cask.
    useHTTPS = true;
    admins = [ "github:mulatta" ];
    database.createLocally = true;

    buildSystems = [ "x86_64-linux" ];

    github = {
      enable = true;
      appId = lib.toInt gen.nixbot-github.files.app-id.value;
      oauthId = gen.nixbot-github.files.oauth-id.value;
      appSecretKeyFile = gen.nixbot-github.files.private-key.path;
      webhookSecretFile = gen.nixbot-github.files.webhook-secret.path;
      oauthSecretFile = gen.nixbot-github.files.oauth-secret.path;
      topic = "build-with-nixbot";
      userAllowlist = [ "mulatta" ];
    };

    niks3 = {
      enable = true;
      package = self.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
      serverUrl = "https://niks3.mulatta.io";
      authTokenFile = gen.nixbot-niks3.files.token.path;
    };
  };

  # Reached only through cask's proxy.
  services.nginx.virtualHosts.${domain}.listen = [
    {
      addr = naru.ipv4;
      port = 80;
    }
    {
      addr = "[${naru.ipv6}]";
      port = 80;
    }
  ];
  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ 80 ];
}
