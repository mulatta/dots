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
  # Operator-level security policy, not per-site content — every vhost
  # serves the same file and points Canonical at mulatta.io.
  # Vhosts wire this in via locations."= /.well-known/security.txt".
  _module.args.securityTxtFile = securityTxtFile;

  _module.args.openpgpkeyDir = openpgpkeyDir;

  # Baseline security response headers for app/SPA vhosts. Concatenated
  # into the vhost's `extraConfig` so nginx's "one add_header at any
  # level suppresses inherited ones" rule does not bite; HSTS is
  # already emitted via recommendedTlsSettings.
  _module.args.securityHeadersConfig = ''
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';

  # Ready-to-merge locations for app/SPA vhosts: serve the shared
  # security.txt at the canonical path and 404 every other /.well-known/
  # probe so upstream SPA fallbacks can't pretend to answer arbitrary
  # well-known paths. Vhost merges this into its own `locations` attr
  # with `//` to keep any vhost-specific entries.
  _module.args.appWellKnownLocations = {
    "= /.well-known/security.txt" = {
      alias = "${securityTxtFile}";
      extraConfig = ''
        default_type "text/plain; charset=utf-8";
      '';
    };
    "~ ^/\\.well-known/".extraConfig = ''
      return 404;
    '';
  };
}
