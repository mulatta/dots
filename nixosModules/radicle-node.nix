{
  config,
  pkgs,
  ...
}:
{
  # SSH key generation via clan vars
  clan.core.vars.generators.radicle = {
    files.ssh-private-key = {
      secret = true;
      owner = "radicle";
    };
    files.ssh-public-key = {
      secret = false;
    };
    runtimeInputs = [ pkgs.openssh ];
    script = ''
      ssh-keygen -t ed25519 -N "" -f $out/ssh-private-key -C "radicle@${config.networking.hostName}"
      ssh-keygen -y -f $out/ssh-private-key > $out/ssh-public-key
    '';
  };

  services.radicle = {
    enable = true;
    privateKeyFile = config.clan.core.vars.generators.radicle.files.ssh-private-key.path;
    publicKey = builtins.readFile config.clan.core.vars.generators.radicle.files.ssh-public-key.path;

    node = {
      openFirewall = true;
      listenAddress = "[::]";
      listenPort = 8776;
    };

    settings = {
      preferredSeeds = [
        "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@seed.radicle.xyz:8776"
        "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@iris.radicle.xyz:8776"
      ];
      node = {
        alias = config.networking.hostName;
        seedingPolicy = {
          default = "block";
          scope = "all";
        };
      };
    };
  };
}
