# A tailnet certificate whose DNS-01 challenge is answered by knot on cask.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = config.networking.hostName;
  generator = "acme-tsig-${host}";
in
{
  options.mulatta.tailnetNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Service names under ts.mulatta.io that this host serves and certifies.";
  };

  config.clan.core.vars.generators.${generator} = import ./tsig.nix { inherit pkgs host; };

  config.security.acme.certs."${host}.ts.mulatta.io" = {
    extraDomainNames = map (name: "${name}.ts.mulatta.io") config.mulatta.tailnetNames;
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
