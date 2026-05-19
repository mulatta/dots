{ pkgs, ... }:

let
  tapsBulwarkConfig =
    (import "${pkgs.path}/nixos/lib/eval-config.nix" {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ./default.nix
        ../../machines/taps/modules/bulwark-webmail.nix
        (
          { lib, pkgs, ... }:
          {
            options.clan.core.vars.generators = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };

            config = {
              clan.core.vars.generators.bulwark-webmail.files.session-secret.path =
                pkgs.writeText "bulwark-webmail-session-secret" "0123456789abcdef0123456789abcdef";
              system.stateVersion = "25.11";
            };
          }
        )
      ];
    }).config;

  mailLocations = tapsBulwarkConfig.services.nginx.virtualHosts."mail.mulatta.io".locations;
  stalwartHeaders = ''
    proxy_set_header Host stalwart.mulatta.io;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  '';
  stalwartProxyLocation = name: location: {
    proxyPass = pkgs.lib.assertMsg (
      location.proxyPass == "http://127.0.0.1:8080"
    ) "mail.mulatta.io ${name} must proxy to Stalwart";
    headers = pkgs.lib.assertMsg (
      location.extraConfig == stalwartHeaders
    ) "mail.mulatta.io ${name} must preserve the Stalwart Host and forwarding headers";
    recommendedProxySettings = pkgs.lib.assertMsg (
      location.recommendedProxySettings == false
    ) "mail.mulatta.io ${name} must not let recommended proxy headers override the Stalwart Host";
  };
in
assert (stalwartProxyLocation "/dav/" mailLocations."/dav/").proxyPass;
assert (stalwartProxyLocation "/dav/" mailLocations."/dav/").headers;
assert (stalwartProxyLocation "/dav/" mailLocations."/dav/").recommendedProxySettings;
assert
  (stalwartProxyLocation "/.well-known/caldav" mailLocations."= /.well-known/caldav").proxyPass;
assert (stalwartProxyLocation "/.well-known/caldav" mailLocations."= /.well-known/caldav").headers;
assert
  (stalwartProxyLocation "/.well-known/caldav" mailLocations."= /.well-known/caldav")
  .recommendedProxySettings;
assert
  (stalwartProxyLocation "/.well-known/carddav" mailLocations."= /.well-known/carddav").proxyPass;
assert
  (stalwartProxyLocation "/.well-known/carddav" mailLocations."= /.well-known/carddav").headers;
assert
  (stalwartProxyLocation "/.well-known/carddav" mailLocations."= /.well-known/carddav")
  .recommendedProxySettings;
assert pkgs.lib.assertMsg (
  mailLocations."= /.well-known/jmap".proxyPass == "http://127.0.0.1:8080/jmap/session"
) "mail.mulatta.io /.well-known/jmap proxy must stay pointed at the Stalwart JMAP session";
assert pkgs.lib.assertMsg (pkgs.lib.hasInfix
  ''sub_filter "https://stalwart.mulatta.io/" "https://mail.mulatta.io/";''
  mailLocations."= /.well-known/jmap".extraConfig
) "mail.mulatta.io /.well-known/jmap must keep Stalwart-to-mail URL rewriting";
assert (stalwartProxyLocation "/jmap/" mailLocations."/jmap/").proxyPass;
assert (stalwartProxyLocation "/jmap/" mailLocations."/jmap/").recommendedProxySettings;
assert pkgs.lib.assertMsg (
  mailLocations."/jmap/".proxyWebsockets == true
) "mail.mulatta.io /jmap/ proxy must keep websocket support";
pkgs.testers.runNixOSTest {
  name = "bulwark-webmail";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ./default.nix ];

      services.bulwark-webmail = {
        enable = true;
        jmapServerUrl = "https://mail.example.com";
        sessionSecretFile = pkgs.writeText "bulwark-webmail-session-secret" "0123456789abcdef0123456789abcdef";
        settingsSync.enable = true;
        kanidm = {
          enable = true;
          origin = "https://idm.example.com";
          clientId = "bulwark-webmail";
          clientSecretFile = pkgs.writeText "bulwark-webmail-oauth-client-secret" "kanidm-client-secret";
          oauthOnly = true;
          autoSso = true;
        };
      };

      system.stateVersion = "25.11";
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("bulwark-webmail.service")
    machine.wait_for_open_port(3000)
    machine.succeed("${pkgs.curl}/bin/curl --fail http://127.0.0.1:3000/api/health | grep healthy")
    machine.succeed("${pkgs.curl}/bin/curl --fail --head --header 'Host: webmail.example.com' --header 'X-Forwarded-Host: webmail.example.com' --header 'X-Forwarded-Proto: https' http://127.0.0.1:3000/")
    machine.succeed("test -d /var/lib/bulwark-webmail/settings")
    machine.succeed("test -d /var/lib/bulwark-webmail/admin")
    machine.succeed("test -d /var/lib/bulwark-webmail/telemetry")
    machine.succeed("test -d /var/lib/bulwark-webmail/version-check")

    pid = machine.succeed("systemctl show --property MainPID --value bulwark-webmail.service").strip()
    env = f"tr '\\0' '\\n' < /proc/{pid}/environ"
    machine.succeed(env + " | grep '^OAUTH_ENABLED=true$'")
    machine.succeed(env + " | grep '^OAUTH_ONLY=true$'")
    machine.succeed(env + " | grep '^AUTO_SSO_ENABLED=true$'")
    machine.succeed(env + " | grep '^OAUTH_CLIENT_ID=bulwark-webmail$'")
    machine.succeed(env + " | grep '^OAUTH_ISSUER_URL=https://idm.example.com/oauth2/openid/bulwark-webmail$'")
    machine.succeed(env + " | grep '^OAUTH_CLIENT_SECRET_FILE=/run/credentials/bulwark-webmail.service/oauth-client-secret$'")
    machine.succeed("grep -x kanidm-client-secret /run/credentials/bulwark-webmail.service/oauth-client-secret")
  '';
}
