# A tailnet certificate whose DNS-01 challenge is answered by knot on cask.
{ config, pkgs, ... }:
let
  host = config.networking.hostName;
  generator = "acme-tsig-${host}";
in
{
  clan.core.vars.generators.${generator} = import ./tsig.nix { inherit pkgs host; };

  security.acme.certs."${host}.ts.mulatta.io" = {
    dnsProvider = "rfc2136";
    environmentFile = pkgs.writeText "acme-rfc2136.env" ''
      RFC2136_NAMESERVER=ns1.mulatta.io
      RFC2136_TSIG_KEY=${host}.acme.mulatta.io.
      RFC2136_TSIG_ALGORITHM=hmac-sha256.
    '';
    credentialFiles.RFC2136_TSIG_SECRET_FILE =
      config.clan.core.vars.generators.${generator}.files.secret.path;
  };
}
