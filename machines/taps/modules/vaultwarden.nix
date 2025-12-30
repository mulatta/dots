{
  config,
  pkgs,
  ...
}:
{
  clan.core.vars.generators.vaultwarden = {
    files.admin-token = {
      secret = true;
      owner = "vaultwarden";
    };

    runtimeInputs = with pkgs; [
      coreutils
      openssl
      libargon2
    ];

    script = ''
      # Generate admin token plaintext (64 random bytes, URL-safe base64)
      PLAINTEXT=$(openssl rand 64 | openssl base64 -A | tr '+/' '-_' | tr -d '=')

      # Generate random salt for argon2 (16 bytes)
      SALT=$(openssl rand -base64 16 | tr -d '\n')

      # Generate argon2id hash (bitwarden preset: m=64MiB, t=3, p=4)
      HASH=$(echo -n "$PLAINTEXT" | argon2 "$SALT" -id -t 3 -m 16 -p 4 -l 32 -e)
      echo "ADMIN_TOKEN='$HASH'" > "$out/admin-token"
    '';
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    config = {
      DOMAIN = "https://bitwarden.mulatta.io";
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;
      SHOW_PASSWORD_HINT = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      LOG_LEVEL = "warn";
    };
  };

  systemd.services.vaultwarden.serviceConfig.EnvironmentFile = [
    config.clan.core.vars.generators.vaultwarden.files.admin-token.path
  ];
}
