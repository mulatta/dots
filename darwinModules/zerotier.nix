{
  config,
  lib,
  pkgs,
  ...
}:
let
  ztDataDir = "/Library/Application Support/ZeroTier/One";
  ztCli = "/usr/local/bin/zerotier-cli";
  ztIdTool = "${pkgs.zerotierone}/bin/zerotier-idtool";

  clanIdentityPath = lib.attrByPath [
    "clan"
    "core"
    "vars"
    "generators"
    "zerotier"
    "files"
    "zerotier-identity-secret"
    "path"
  ] null config;

  clanNetworkId = lib.attrByPath [ "clan" "core" "networking" "zerotier" "networkId" ] null config;
in
{
  options.services.zerotierone = {
    enable = lib.mkEnableOption "ZeroTier One";

    joinNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional (clanNetworkId != null) clanNetworkId;
      description = "List of ZeroTier network IDs to join on startup (auto-detected from clan if available)";
    };

    identitySecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = clanIdentityPath;
      description = "Path to ZeroTier identity.secret file (auto-detected from clan.core.vars if available)";
    };
  };

  config = lib.mkIf config.services.zerotierone.enable {
    # Add nix zerotierone for zerotier-idtool
    environment.systemPackages = [ pkgs.zerotierone ];

    # NOTE: We don't create our own launchd daemon here.
    # ZeroTier must be installed via Homebrew cask (zerotier-one) which includes
    # the system extension required for network interface creation on macOS.
    # The homebrew cask installs its own LaunchDaemon.

    # Install identity and join networks on activation
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Setting up ZeroTier..."

      # Ensure ZeroTier data directory exists
      mkdir -p "${ztDataDir}"

      ${lib.optionalString (config.services.zerotierone.identitySecretFile != null) ''
        # Install clan-managed identity if different from current
        if [ -f "${config.services.zerotierone.identitySecretFile}" ]; then
          CURRENT_IDENTITY=""
          if [ -f "${ztDataDir}/identity.secret" ]; then
            CURRENT_IDENTITY=$(cat "${ztDataDir}/identity.secret" 2>/dev/null || true)
          fi
          NEW_IDENTITY=$(cat "${config.services.zerotierone.identitySecretFile}")

          if [ "$CURRENT_IDENTITY" != "$NEW_IDENTITY" ]; then
            echo "Installing clan-managed ZeroTier identity..."
            # Stop ZeroTier daemon first
            launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
            sleep 1

            # Backup existing identity if present
            if [ -f "${ztDataDir}/identity.secret" ]; then
              cp "${ztDataDir}/identity.secret" "${ztDataDir}/identity.secret.bak.$(date +%s)"
              rm -f "${ztDataDir}/identity.public"
            fi
            # Install new identity
            cp "${config.services.zerotierone.identitySecretFile}" "${ztDataDir}/identity.secret"
            chmod 600 "${ztDataDir}/identity.secret"
            # Generate public key from secret
            ${ztIdTool} getpublic "${ztDataDir}/identity.secret" > "${ztDataDir}/identity.public"

            # Restart daemon to pick up new identity
            echo "Restarting ZeroTier daemon with new identity..."
            launchctl load /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
          fi
        fi
      ''}

      # Wait for zerotier daemon to be ready (up to 15 seconds)
      for i in {1..15}; do
        if ${ztCli} info >/dev/null 2>&1; then
          break
        fi
        echo "Waiting for ZeroTier daemon... ($i/15)"
        sleep 1
      done

      ${lib.concatMapStringsSep "\n" (network: ''
        if ! ${ztCli} listnetworks 2>/dev/null | grep -q "${network}"; then
          echo "Joining ZeroTier network ${network}..."
          ${ztCli} join "${network}" || true
        fi
      '') config.services.zerotierone.joinNetworks}
    '';
  };
}
