{
  self,
  pkgs,
  ...
}:
{
  imports = [
    self.nixosModules.default
    self.inputs.srvos.nixosModules.server
    self.inputs.disko.nixosModules.disko
    # Main lacks the PHP 8.4.27 overlay; auto-upgrading would roll Nextcloud back to 8.4.26.
    # ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/docker-zfs.nix
    ../../nixosModules/postgresql.nix
    # Radicle node transport leaks private repos until the next major release.
    # ../../nixosModules/radicle-mulatta.nix
    ./modules/agentgateway.nix
    ./modules/disko.nix
    ./modules/hermes
    ./modules/hindsight
    ./modules/home-assistant.nix
    ./modules/jellyfin
    ./modules/linkwarden.nix
    ./modules/minecraft.nix
    ./modules/miniflux
    ./modules/network.nix
    ./modules/neko.nix
    ./modules/nextcloud.nix
    ./modules/paperless.nix
    ./modules/private-service.nix
    ./modules/rsshub.nix
    ./modules/searxng.nix
    ./modules/sparkyfitness.nix
    ./modules/tailscale.nix
    ./modules/trek.nix
  ];

  networking.hostName = "malt";
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ self.overlays.default ];

  # Enable aarch64 emulation for building Raspberry Pi images
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-compute-runtime
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    btop
  ];

  programs.fish.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = "25.05";
}
