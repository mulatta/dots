{
  config,
  pkgs,
  ...
}:
{
  clan.core.vars.generators.ntfy = {
    files.env = {
      secret = true;
      owner = "ntfy-sh";
    };
    files.password-plaintext.secret = true;

    runtimeInputs = with pkgs; [
      coreutils
      gnused
      openssl
      apacheHttpd # for htpasswd (bcrypt)
    ];

    script = ''
      PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
      HASH=$(htpasswd -nbBC 10 "" "$PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/')
      echo "NTFY_AUTH_USERS='seungwon:$HASH:admin'" > "$out/env"
      echo "$PASSWORD" > "$out/password-plaintext"
    '';
  };

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.clan.core.vars.generators.ntfy.files.env.path;
    settings = {
      base-url = "https://ntfy.mulatta.io";
      listen-http = "127.0.0.1:2586";
      behind-proxy = true;
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
      enable-signup = false;
      enable-login = true;
    };
  };
}
