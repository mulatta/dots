{ ... }:
let
  seungwonKey = [
    # Secretive Secure Enclave key on rhesus (daily SSH from laptop).
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAbiIX1IpgsaylNgtDb04IM4jQKlU+RVwDr8YGfXLwuHWn3xydzTYeg3o/T9UX/j2326D7tnL7kMq7XvmhuSd8Y= ssh@secretive.rhesus.local"
  ];

in
{
  programs.zsh.enable = true;
  users.users.seungwon = {
    home = "/home/seungwon";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = "/run/current-system/sw/bin/zsh";
    openssh.authorizedKeys.keys = seungwonKey;
  };

  users.users.root = {
    shell = "/run/current-system/sw/bin/bash";
    openssh.authorizedKeys.keys = seungwonKey;
  };

  # SSH keys are the routine authentication path. Clan's per-machine root
  # password remains available for break-glass console access.
  security.sudo.wheelNeedsPassword = false;
}
