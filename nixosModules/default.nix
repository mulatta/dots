{
  self,
  lib,
  ...
}:
{
  imports = [
    self.inputs.srvos.nixosModules.common
    self.inputs.srvos.nixosModules.mixins-terminfo
    self.inputs.srvos.nixosModules.mixins-nix-experimental
    self.inputs.srvos.nixosModules.mixins-trusted-nix-caches
    ./acme.nix
    ./dns-client.nix
    ./i18n.nix
    ./minimal-docs.nix
    ./nftables.nix
    ./nix-daemon.nix
    ./thermald.nix
    ./users.nix
    ./zerotier.nix
  ];

  srvos.flake = self;
  clan.core.settings.state-version.enable = true;

  # Timezone - Asia/Seoul for all machines (override srvos UTC default)
  time.timeZone = lib.mkForce "Asia/Seoul";

  # Disable unnecessary documentation to reduce build time
  documentation.info.enable = false;
  documentation.doc.enable = false;

  # Use memory more efficiently
  zramSwap.enable = lib.mkDefault true;

  security.sudo.execWheelOnly = lib.mkForce false;
  programs.nano.enable = false;
}
