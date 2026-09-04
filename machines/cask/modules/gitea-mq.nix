{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  domain = "mq.mulatta.io";
  port = 18980;
  gen = config.clan.core.vars.generators;
in
{
  imports = [ self.inputs.gitea-mq.nixosModules.default ];

  clan.core.vars.generators.mulatta-mq = {
    files.app-id.secret = false;
    files.private-key.secret = true;
    files.webhook-secret.secret = true;
    prompts.app-id.description = "GitHub App ID for mulatta-mq";
    prompts.private-key = {
      description = "GitHub App private key (PEM) for mulatta-mq";
      type = "multiline-hidden";
      persist = true;
    };
    script = ''
      tr -d '\r\n' < "$prompts/app-id" > "$out/app-id"
      cp "$prompts/private-key" "$out/private-key"
      ${pkgs.xkcdpass}/bin/xkcdpass -n 6 -d - > "$out/webhook-secret"
    '';
  };

  services.postgresql.ensureDatabases = [ "gitea-mq" ];
  services.postgresql.ensureUsers = [
    {
      name = "gitea-mq";
      ensureDBOwnership = true;
    }
  ];

  services.gitea-mq = {
    enable = true;
    listenAddr = "127.0.0.1:${toString port}";
    externalUrl = "https://${domain}";
    hideRefFromClients = false;
    batchMax = 5;
    github = {
      appId = lib.toInt gen.mulatta-mq.files.app-id.value;
      privateKeyFile = gen.mulatta-mq.files.private-key.path;
      webhookSecretFile = gen.mulatta-mq.files.webhook-secret.path;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    locations."/".extraConfig = ''
      proxy_pass http://127.0.0.1:${toString port};
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    '';
  };
}
