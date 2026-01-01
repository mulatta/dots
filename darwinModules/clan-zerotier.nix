# Darwin implementation of clan's zerotier vars generator and networking options
# This mirrors nixosModules/clanCore/zerotier/default.nix for Darwin
{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.clan.core.networking.zerotier;

  # Access clan-core lib for getPublicValue
  clanLib = self.inputs.clan-core.lib;

  # Get network ID from controller machine's vars
  getNetworkId =
    if cfg.controller.machineName != null then
      clanLib.getPublicValue {
        flake = config.clan.core.settings.directory;
        machine = cfg.controller.machineName;
        generator = "zerotier";
        file = "zerotier-network-id";
        default = null;
      }
    else
      null;
in
{
  options.clan.core.networking.zerotier = {
    enable = lib.mkEnableOption "ZeroTier networking for Darwin";

    networkId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = getNetworkId;
      description = "ZeroTier network ID (auto-detected from controller if not set)";
    };

    controller.machineName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name of the machine that acts as ZeroTier controller";
    };
  };

  config = lib.mkIf cfg.enable {
    # Set up vars generator for zerotier identity
    clan.core.vars.generators.zerotier = {
      files.zerotier-identity-secret = {
        secret = true;
      };
      files.zerotier-ip = { };
      # Use the same generation script as NixOS
      script = ''
        ${pkgs.zerotierone}/bin/zerotier-idtool generate "$out/zerotier-identity-secret"
        IDENTITY_PUBLIC=$(${pkgs.zerotierone}/bin/zerotier-idtool getpublic "$out/zerotier-identity-secret")
        NODE_ID=$(echo "$IDENTITY_PUBLIC" | cut -d: -f1)
        # Generate IPv6 address from network ID and node ID
        NETWORK_ID="${toString cfg.networkId}"
        if [ -n "$NETWORK_ID" ]; then
          # ZeroTier IPv6 format: fd + first 15 hex of network + 10 hex of node
          PREFIX="fd''${NETWORK_ID:0:2}:''${NETWORK_ID:2:4}:''${NETWORK_ID:6:4}:''${NETWORK_ID:10:4}"
          SUFFIX="''${NODE_ID:0:2}''${NODE_ID:2:2}:''${NODE_ID:4:4}:''${NODE_ID:6:2}''${NODE_ID:8:2}"
          echo "$PREFIX:$SUFFIX" > "$out/zerotier-ip"
        fi
      '';
    };

    # Configure ZeroTier service to use clan-managed identity and network
    services.zerotierone = {
      enable = true;
      joinNetworks = lib.mkIf (cfg.networkId != null) [ cfg.networkId ];
      identitySecretFile = config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
    };
  };
}
