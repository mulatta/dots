{
  imports = [ ./radicle-node.nix ];

  services.radicle = {
    # DIDs to follow (auto-accept repos from these identities)
    followDids = [
      "did:key:z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY" # taps
      "did:key:z6MkrAWJwxJwP8DPKL7aaMQpDq9FurZ6WfrnaRz3uVAUnPg9" # dots_actions (GitHub)
      "did:key:z6MkkGbVHDVLst7JZgrH8iTCK6YGg4GJKAuEoPEcrokykNkk" # mulatta (me)
    ];

    # Repositories to seed
    seedRepositories = [
      "rad:z4SMvWSqp66q9fMnmvbZ2uhWmn28y" # dots
      "rad:z3FM8sqh54MUW273vfZCExrgxYHpn" # blog
      "rad:z3EM9Hr4NCQ6oi8NanciTbURWv89S" # homepage (mulatta.io landing)
      "rad:zsn1Vdw1bmymHfWkZXyb5yiCEYyL" # cv
    ];

    # Personal nodes to connect
    # NAT-behind nodes (malt, pint) use ZeroTier addresses since they have no public DNS
    connectNodes = [
      "z6MkkV8YjYkBowG8oFyMqwe1Lnp3B9TmJtTSjNNFY6mcxGJY@rad.mulatta.io:8776"
      "z6MkqRXPuCo1ykP1korSc2sMKjTQxyHcvuSG3D2CQ17ZmFgd@malt.x:8776"
      "z6MkiZyr4pSkPx9pdjF7qH2ns3Sq2PhptbMmJzKTAoEfcfnd@pint.x:8776"
    ];
  };
}
