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
    ../../nixosModules/auto-upgrade.nix
    ../../nixosModules/disko-zfs.nix
    ../../nixosModules/radicle-mulatta.nix
    ./modules/backup.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/linkwarden.nix
    ./modules/miniflux
    ./modules/n8n
    ./modules/network.nix
    ./modules/nextcloud.nix
    ./modules/opencrow
    ./modules/paperless.nix
    ./modules/restate.nix
    ./modules/rsshub.nix
    ./modules/vikunja.nix
  ];

  clan.core.networking.targetHost = "root@malt.x";

  disko.rootDisk = "/dev/nvme0n1";

  networking.hostName = "malt";
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ self.overlays.dots ];

  # UEFI boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable aarch64 emulation for building Raspberry Pi images
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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
