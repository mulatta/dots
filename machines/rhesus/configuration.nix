{
  self,
  pkgs,
  lib,
  ...
}:
{
  # Use WireGuard .x domain for clan connectivity (mkForce to override defaults)
  clan.core.networking.targetHost = lib.mkForce "root@rhesus.x";
  system.primaryUser = "seungwon";

  networking.hostName = "rhesus";
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  imports = [
    self.inputs.srvos.darwinModules.common
    self.inputs.srvos.darwinModules.mixins-terminfo
    self.inputs.srvos.darwinModules.mixins-nix-experimental
    self.inputs.sops-nix.darwinModules.sops
    ../../darwinModules/docker.nix
    ../../darwinModules/homebrew.nix
    ../../darwinModules/linux-builder.nix
    ../../darwinModules/nix-daemon.nix
    ../../darwinModules/nix-index.nix
    ../../darwinModules/sudo.nix
    ../../darwinModules/desktop.nix
    ../../darwinModules/zerotier.nix
    ../../darwinModules/clan-zerotier.nix
    ../../darwinModules/dns-client.nix
  ];

  # ZeroTier VPN - uses clan's self-hosted controller on taps
  clan.core.networking.zerotier = {
    enable = true;
    controller.machineName = "taps";
  };

  system.activationScripts.postActivation.text = ''
    # disable spotlight
    # launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist >/dev/null 2>&1 || true
    # disable fseventsd on /nix volume
    mkdir -p /nix/.fseventsd
    test -e /nix/.fseventsd/no_log || touch /nix/.fseventsd/no_log
  '';

  # Use user's existing age key for sops-nix
  sops.age.keyFile = "/Users/seungwon/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ ];

  users.users.seungwon.home = "/Users/seungwon";

  environment.systemPackages = [
    self.packages.${pkgs.stdenv.hostPlatform.system}.systemctl-macos
    pkgs.nixos-rebuild
    pkgs.python3
    pkgs.uv
    pkgs.tree
    pkgs.curl
    pkgs.wget
    pkgs.nodejs_24
    pkgs.parallel
  ];

  system.stateVersion = 6;

  srvos.flake = self;
}
