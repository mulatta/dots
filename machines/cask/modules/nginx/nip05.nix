{
  config,
  lib,
  pkgs,
  ...
}:
let
  named = lib.mapAttrs (_: identity: identity.pubkey) (
    lib.filterAttrs (_: identity: identity.pubkey != null) config.mulatta.nostr.identities
  );
  uniqueHexes = lib.unique (builtins.attrValues named);

  nostrJson = {
    names = {
      _ = config.mulatta.nostr.identities.mulatta.pubkey;
    }
    // named;
    relays = lib.listToAttrs (
      map (h: {
        name = h;
        value = config.mulatta.nostr.dmRelays;
      }) uniqueHexes
    );
  };

  nostrJsonFile = pkgs.writeText "nostr.json" (builtins.toJSON nostrJson);
in
{
  services.nginx.virtualHosts."mulatta.io".locations."= /.well-known/nostr.json" = {
    alias = nostrJsonFile;
    extraConfig = ''
      add_header Access-Control-Allow-Origin "*" always;
      add_header Cache-Control "public, max-age=3600";
      default_type application/json;
    '';
  };
}
