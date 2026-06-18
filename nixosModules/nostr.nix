{
  self,
  lib,
  ...
}:
let
  readVarFile = self.lib.readVarFile;
in
{
  options.mulatta.nostr = {
    identities = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            pubkey = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              description = "Nostr public key in hex form.";
            };
          };
        }
      );
      default = { };
      description = "Shared Nostr identities used by NIP-05, Blossom, and agents.";
    };

    dmRelays = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default NIP-17 DM relays.";
    };

    blossomServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default Blossom/NIP-96 media servers.";
    };
  };

  config = {
    mulatta.nostr = {
      identities = {
        mulatta.pubkey = lib.mkDefault "562c307c7e0d56d818e50c7c6b9a5dd6aa353ccbe087f7ee68c61c12674098aa";
        noa.pubkey = lib.mkDefault (readVarFile "malt" "opencrow" "nostr-public-key");
      };

      dmRelays = lib.mkDefault [
        "wss://relay.mulatta.io"
        "wss://relay.primal.net"
        "wss://nos.lol"
      ];

      blossomServers = lib.mkDefault [
        "https://blossom.mulatta.io"
      ];
    };
  };
}
