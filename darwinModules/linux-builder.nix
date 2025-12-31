{ lib, ... }:
{
  nix.linux-builder = {
    enable = true;
    maxJobs = 8;

    config = {
      virtualisation = {
        cores = 8;
        memorySize = lib.mkForce (8 * 1024);
        diskSize = lib.mkForce (100 * 1024);
      };
    };
  };

  nix.settings.trusted-users = [
    "@admin"
    "seungwon"
  ];
}
