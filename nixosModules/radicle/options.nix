{ lib, ... }:
{
  options.services.radicle = {
    seedRepositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of Radicle repository IDs to automatically seed.
        These will also be pinned in the web interface.
      '';
      example = [ "rad:z2dqRKkK5yu89w3CMX2dVsYrRwvFk" ];
    };

    autoSeedFollowed = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically discover and seed all repositories from followed users.
      '';
    };

    followDids = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of DIDs to follow. Repos from these users will be accepted.
      '';
      example = [ "did:key:z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY" ];
    };

    connectNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of nodes to maintain persistent connections with.
        Format: NID@host:port
      '';
      example = [ "z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY@rad.mulatta.io:8776" ];
    };
  };
}
