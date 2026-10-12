{ ... }:
{
  allowUnfree = true;
  # Only public repositories are mirrored, so unencrypted node traffic is accepted.
  permittedInsecurePackages = [ "radicle-node-1.10.3" ];
}
