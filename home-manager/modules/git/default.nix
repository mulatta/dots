{ ... }:
{
  imports = [
    ./git.nix
    ./gh.nix
    ./jujutsu.nix
  ];

  sops.secrets.id_ed25519_pub = { };
}
