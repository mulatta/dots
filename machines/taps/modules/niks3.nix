{
  self,
  config,
  pkgs,
  ...
}:
{
  imports = [ self.inputs.niks3.nixosModules.niks3 ];

  clan.core.vars.generators.niks3 = {
    files.api-token = {
      secret = true;
      owner = "niks3";
    };
    files.signing-key = {
      secret = true;
      owner = "niks3";
    };
    files.signing-key-pub.secret = false;

    files.r2-access-key = {
      secret = true;
      owner = "niks3";
    };
    files.r2-secret-key = {
      secret = true;
      owner = "niks3";
    };

    prompts.r2-access-key = {
      description = "R2 Access Key ID";
      type = "hidden";
      persist = true;
    };
    prompts.r2-secret-key = {
      description = "R2 Secret Access Key";
      type = "hidden";
      persist = true;
    };

    runtimeInputs = with pkgs; [
      coreutils
      openssl
      nix
    ];

    script = ''
      # API token (min 36 chars)
      openssl rand -base64 48 > "$out/api-token"

      # Ed25519 signing key
      nix key generate-secret --key-name cache.mulatta.io-1 > "$out/signing-key"
      nix key convert-secret-to-public < "$out/signing-key" > "$out/signing-key-pub"

      # R2 credentials from prompts
      cat "$prompts/r2-access-key" > "$out/r2-access-key"
      cat "$prompts/r2-secret-key" > "$out/r2-secret-key"
    '';
  };

  services.niks3 = {
    enable = true;
    httpAddr = "127.0.0.1:5751";

    s3 = {
      endpoint = "a36871be6860124304dfb5c3b3eb8c1a.r2.cloudflarestorage.com";
      bucket = "cache";
      useSSL = true;
      accessKeyFile = config.clan.core.vars.generators.niks3.files.r2-access-key.path;
      secretKeyFile = config.clan.core.vars.generators.niks3.files.r2-secret-key.path;
    };

    database.createLocally = true;

    apiTokenFile = config.clan.core.vars.generators.niks3.files.api-token.path;
    signKeyFiles = [ config.clan.core.vars.generators.niks3.files.signing-key.path ];

    gc = {
      enable = true;
      olderThan = "720h";
      schedule = "daily";
    };

    nginx = {
      enable = true;
      domain = "niks3.mulatta.io";
      enableACME = true;
      forceSSL = true;
    };

    cacheUrl = "https://cache.mulatta.io";
  };

  # Additional nginx tuning for niks3 (large NAR uploads)
  services.nginx.virtualHosts."niks3.mulatta.io".locations."/".extraConfig = ''
    proxy_buffering off;
    proxy_request_buffering off;
  '';
}
