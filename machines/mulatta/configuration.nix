{
  config,
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/users.nix
    self.inputs.apple-silicon.nixosModules.default
    self.inputs.srvos.nixosModules.common
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.sops-nix.nixosModules.sops
  ];

  clan.core.networking.targetHost = lib.mkForce "root@mulatta.local";
  clan.core.vars.generators.mulatta-password = {
    files.password-hash.neededFor = "users";
    files.password.deploy = false;
    runtimeInputs = [
      pkgs.mkpasswd
      pkgs.xkcdpass
    ];
    prompts.password.type = "hidden";
    script = ''
       prompt_value="$(cat "$prompts"/password)"
      if [[ -n "''${prompt_value-}" ]]; then
        echo "$prompt_value" | tr -d "\n" > "$out"/password
      else
        xkcdpass --numwords 4 --delimiter - --count 1 | tr -d "\n" > "$out"/password
      fi
      mkpasswd -s -m sha-512 < "$out"/password | tr -d "\n" > "$out"/password-hash
    '';
  };

  networking.hostName = "mulatta";

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [self.inputs.apple-silicon.overlays.apple-silicon-overlay];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.asahi.peripheralFirmwareDirectory = /boot/asahi;
  hardware.asahi.extractPeripheralFirmware = true;

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;
  networking.wireless.iwd = {
    enable = true;
    settings.General.EnableNetworkConfiguration = true;
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  environment.systemPackages = [
    pkgs.python3
    pkgs.nixos-rebuild
  ];

  srvos.flake = self;

  system.stateVersion = "25.11";
}
