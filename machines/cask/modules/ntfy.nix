{
  config,
  pkgs,
  ...
}:
let
  mkAccountGenerator =
    { username, role }:
    {
      files.env.secret = true;
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
        echo "NTFY_AUTH_USERS='${username}:$HASH:${role}'" > "$out/env"
        echo "$PASSWORD" > "$out/password-plaintext"
      '';
    };
in
{
  clan.core.vars.generators = {
    ntfy = mkAccountGenerator {
      username = "seungwon";
      role = "admin";
    };
    ntfy-automation = mkAccountGenerator {
      username = "automation";
      role = "user";
    };
    ntfy-job-01 = mkAccountGenerator {
      username = "job-01";
      role = "user";
    };
  };

  systemd.services.ntfy-sh = {
    # EnvironmentFile is read before preStart too, when the file may not exist yet.
    serviceConfig = {
      EnvironmentFile = "-/run/ntfy-sh/auth.env";
      # DynamicUser identities do not exist while activation installs secrets.
      LoadCredential = map (name: "${name}:${config.clan.core.vars.generators.${name}.files.env.path}") [
        "ntfy"
        "ntfy-automation"
        "ntfy-job-01"
      ];
    };
    preStart = ''
      umask 077
      source "$CREDENTIALS_DIRECTORY/ntfy"
      admin_users="$NTFY_AUTH_USERS"
      source "$CREDENTIALS_DIRECTORY/ntfy-automation"
      automation_users="$NTFY_AUTH_USERS"
      source "$CREDENTIALS_DIRECTORY/ntfy-job-01"
      printf "NTFY_AUTH_USERS='%s,%s,%s'\n" "$admin_users" "$automation_users" "$NTFY_AUTH_USERS" > /run/ntfy-sh/auth.env
    '';
  };

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.mulatta.io";
      listen-http = "127.0.0.1:2586";
      behind-proxy = true;
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
      auth-access = [
        "automation:automation:write-only"
        "automation:job-01:write-only"
        "job-01:job-01:read-only"
        "job-01:automation:write-only"
      ];
      enable-signup = false;
      enable-login = true;
    };
  };
  services.nginx.virtualHosts."ntfy.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";
    locations."/" = {
      proxyPass = "http://127.0.0.1:2586";
      proxyWebsockets = true;
    };
  };
}
