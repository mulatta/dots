{
  self,
  pkgs,
  lib,
  ...
}:
{
  clan.core.networking.targetHost = lib.mkForce "root@rhesus.local";
  system.primaryUser = "seungwon";

  networking.hostName = "rhesus";
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  imports = [
    self.inputs.srvos.darwinModules.common
    self.inputs.srvos.darwinModules.mixins-terminfo
    self.inputs.srvos.darwinModules.mixins-nix-experimental
    self.inputs.sops-nix.darwinModules.sops
    ../../modules/darwin/app-store
    ../../modules/darwin/docker.nix
    ../../modules/darwin/homebrew.nix
    ../../modules/darwin/nix-daemon.nix
    ../../modules/darwin/nix-index.nix
    ../../modules/darwin/sudo.nix
    ../../modules/darwin/desktop.nix
  ];

  system.activationScripts.postActivation.text = ''
    # disable spotlight
    launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist >/dev/null 2>&1 || true
    # disable fseventsd on /nix volume
    mkdir -p /nix/.fseventsd
    test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
  '';

  sops.age.keyFile = "/Library/Application Support/sops-nix/age-keys.txt";

  users.users.seungwon.home = "/Users/seungwon";

  environment.systemPackages = [
    self.packages.${pkgs.system}.systemctl-macos
    pkgs.nixos-rebuild
    pkgs.python3
    pkgs.uv
    pkgs.podman
    pkgs.tree
    pkgs.curl
    pkgs.wget
    pkgs.nodejs_24
  ];

  system.stateVersion = 6;

  srvos.flake = self;
}
