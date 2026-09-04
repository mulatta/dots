# Mirror GitHub repositories into the public Radicle node.
{
  config,
  pkgs,
  self,
  ...
}:
let
  credentialsDirectory = "/run/credentials/radicle-mirror.service";
  generators = config.clan.core.vars.generators;
in
{
  imports = [ self.inputs.radicle-mirror.nixosModules.default ];

  services.radicle-mirror = {
    enable = true;
    package = self.inputs.radicle-mirror.packages.${pkgs.stdenv.hostPlatform.system}.default;
    addr = "127.0.0.1:4128";
    ghAppId = 4741113;
    allowedOwners = [ "mulatta" ];
    mirroredForks = [
      "mulatta/nixpkgs"
      "mulatta/noctalia-plugins"
    ];
    delegates = [ "did:key:z6MkkGbVHDVLst7JZgrH8iTCK6YGg4GJKAuEoPEcrokykNkk" ];
    workers = 1;

    p2pListen = [ "0.0.0.0:8776" ];
    p2pExternalAddresses = [ "rad.mulatta.io:8776" ];
    p2pConnect = [ ];
    explorerUrl = "https://rad.mulatta.io/nodes/rad.mulatta.io/{rid}/commits/{sha}";

    ghAppKeyPath = "${credentialsDirectory}/github-app-key";
    webhookSecretPath = "${credentialsDirectory}/webhook-secret";
    radicleKeyPath = "${credentialsDirectory}/radicle-key";
  };

  systemd.services.radicle-mirror.serviceConfig = {
    LoadCredential = [
      "github-app-key:${generators.radicle-mirror-github-key.files.private-key.path}"
      "webhook-secret:${generators.radicle-mirror-webhook.files.secret.path}"
      "radicle-key:${generators.radicle-mirror-key.files.private-key.path}"
    ];
    MemoryHigh = "768M";
    MemoryMax = "1G";
  };

  clan.core.vars.generators = {
    radicle-mirror-github-key = {
      files.private-key.secret = true;
      prompts.private-key = {
        description = "GitHub App private key (PEM) for radicle-mirror";
        type = "multiline";
        persist = true;
      };
      script = ''
        cp "$prompts/private-key" "$out/private-key"
      '';
    };

    radicle-mirror-webhook = {
      files.secret.secret = true;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl rand -hex 32 > "$out/secret"
      '';
    };

    radicle-mirror-key = {
      files.private-key.secret = true;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C radicle-mirror@cask -f "$out/private-key"
        rm "$out/private-key.pub"
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [ 8776 ];
  services.nginx.virtualHosts."radicle-mirror.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    # Signature validation happens in radicle-mirror; expose no admin surface.
    locations."= /github" = {
      proxyPass = "http://127.0.0.1:4128";
      recommendedProxySettings = true;
    };
    locations."/".return = "404";
  };
}
