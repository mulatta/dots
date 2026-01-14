# Personal Radicle configuration for mulatta
# Repositories, DIDs, and nodes for personal infrastructure
{ ... }:
{
  imports = [ ./radicle-node.nix ];

  services.radicle = {
    # DIDs to follow (auto-accept repos from these identities)
    followDids = [
      "did:key:z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY" # taps
      "did:key:z6MkrAWJwxJwP8DPKL7aaMQpDq9FurZ6WfrnaRz3uVAUnPg9" # dots_actions (GitHub)
    ];

    # Repositories to seed
    seedRepositories = [
      "rad:z4SMvWSqp66q9fMnmvbZ2uhWmn28y" # dots
    ];

    # Personal nodes to connect
    connectNodes = [
      "z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY@rad.mulatta.io:8776"
      "z6MkqRXPuCo1ykP1korSc2sMKjTQxyHcvuSG3D2CQ17ZmFgd@malt.mulatta.io:8776"
      "z6MkiZyr4pSkPx9pdjF7qH2ns3Sq2PhptbMmJzKTAoEfcfnd@pint.mulatta.io:8776"
    ];
  };
}
