{
  config,
  pkgs,
  ...
}:
let
  mkAccountGenerator =
    { username, role }:
    {
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
  };

  systemd.services.ntfy-sh = {
    # EnvironmentFile is read before preStart too, when the file may not exist yet.
    serviceConfig.EnvironmentFile = "-/run/ntfy-sh/auth.env";
    preStart = ''
      umask 077
      source ${config.clan.core.vars.generators.ntfy.files.env.path}
      admin_users="$NTFY_AUTH_USERS"
      source ${config.clan.core.vars.generators.ntfy-automation.files.env.path}
      printf "NTFY_AUTH_USERS='%s,%s'\n" "$admin_users" "$NTFY_AUTH_USERS" > /run/ntfy-sh/auth.env
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
      auth-access = [ "automation:automation:write-only" ];
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
