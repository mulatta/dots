{ pkgs, ... }:
let
  # RFC 9116 security.txt. Must be refreshed before the Expires date —
  # bump this string and redeploy. A Vikunja reminder task should anchor
  # the renewal schedule.
  expires = "2027-04-22T00:00:00Z";

  # WKD (Web Key Directory, RFC 7929) stub directory. Serves a minimal
  # policy file today so `gpg --auto-key-locate wkd` queries do not
  # land on SPA fallbacks; when a real key is published, drop the
  # armored binary at openpgpkey/hu/<z-base32-sha1-of-localpart>.
  openpgpkeyDir = pkgs.runCommand "openpgpkey" { } ''
    mkdir -p $out/hu
    touch $out/policy
  '';
  securityTxtFile = pkgs.writeText "security.txt" ''
    Contact: mailto:security@mulatta.io
    Expires: ${expires}
    Preferred-Languages: en, ko
    Canonical: https://mulatta.io/.well-known/security.txt
  '';
in
{
  services.nginx.virtualHosts = {
    "home.mulatta.io".locations = {
      "= /.well-known/security.txt".return = "308 https://mulatta.io/.well-known/security.txt";
      "~ ^/\.well-known/".extraConfig = "return 404;";
    };
    "relay.mulatta.io".locations = {
      "= /.well-known/security.txt".return = "308 https://mulatta.io/.well-known/security.txt";
      "~ ^/\.well-known/".extraConfig = "return 404;";
    };
    "tasks.mulatta.io".locations = {
      "= /.well-known/security.txt".return = "308 https://mulatta.io/.well-known/security.txt";
      "~ ^/\.well-known/".extraConfig = "return 404;";
    };
    "mulatta.io".locations = {
      "= /.well-known/security.txt" = {
        alias = securityTxtFile;
        extraConfig = ''
          default_type "text/plain; charset=utf-8";
        '';
      };
      "^~ /.well-known/openpgpkey/" = {
        alias = "${openpgpkeyDir}/";
        extraConfig = ''
          default_type "application/octet-stream";
        '';
      };
    };
  };
}
