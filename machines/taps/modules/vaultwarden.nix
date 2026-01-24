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
    files.admin-token-plaintext.secret = true;

    runtimeInputs = with pkgs; [
      coreutils
      openssl
      libargon2
    ];

    script = ''
      PLAINTEXT=$(openssl rand 64 | openssl base64 -A | tr '+/' '-_' | tr -d '=')
      SALT=$(openssl rand -base64 16 | tr -d '\n')
      HASH=$(echo -n "$PLAINTEXT" | argon2 "$SALT" -id -t 3 -m 16 -p 4 -l 32 -e)
      echo "ADMIN_TOKEN='$HASH'" > "$out/admin-token"
      echo "$PLAINTEXT" > "$out/admin-token-plaintext"
    '';
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = config.clan.core.vars.generators.vaultwarden.files.admin-token.path;
    config = {
      DATABASE_URL = "postgresql:///vaultwarden?host=/run/postgresql";
      DOMAIN = "https://vaultwarden.mulatta.io";
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      IP_HEADER = "X-Forwarded-For";
      LOG_LEVEL = "warn";
    };
  };
}
