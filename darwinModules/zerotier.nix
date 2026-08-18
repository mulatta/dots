{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.clan.core.networking.zerotier;

  ztDataDir = "/Library/Application Support/ZeroTier/One";
  ztCli = "/usr/local/bin/zerotier-cli";
  ztIdTool = "${pkgs.zerotierone}/bin/zerotier-idtool";
  machineName = config.clan.core.settings.machine.name;
  instanceName = "zerotier";
  identityGenerator = "zerotier-identity-${machineName}";
  networkGenerator = "zerotier-network-${instanceName}";
  ipGenerator = "zerotier-ip-${machineName}-${instanceName}";
  zerotierTools = config.clan.core.clanPkgs.zerotier-members;

  # Access clan-core lib for getPublicValue
  clanLib = self.inputs.clan-core.lib;

  # Network IDs are shared by all members in Clan's multi-instance layout.
  getNetworkId = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    generator = networkGenerator;
    file = "network-id";
    default = null;
  };

  readVarFile = self.lib.readVarFile;

  # ZeroTier IPs from Clan's shared multi-instance vars
  zerotierIPs = {
    taps = readVarFile null "zerotier-ip-taps-zerotier" "ip";
    malt = readVarFile null "zerotier-ip-malt-zerotier" "ip";
    pint = readVarFile null "zerotier-ip-pint-zerotier" "ip";
    rhesus = readVarFile null "zerotier-ip-rhesus-zerotier" "ip";
  };

  tapsZerotierIP = zerotierIPs.taps;

  mkHostsEntries =
    ips: domain:
    lib.concatStringsSep "\n" (
      lib.filter (x: x != "") (
        lib.mapAttrsToList (name: ip: if ip != null then "${ip} ${name}.${domain}" else "") ips
      )
    );
in
{
  options.clan.core.networking.zerotier = {
    enable = lib.mkEnableOption "ZeroTier networking for Darwin";

    networkId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = getNetworkId;
      description = "ZeroTier network ID (auto-detected from controller if not set)";
    };

  };

  options.services.zerotierone = {
    enable = lib.mkEnableOption "ZeroTier One";

    joinNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional (cfg.networkId != null) cfg.networkId;
      description = "List of ZeroTier network IDs to join on startup";
    };

    identitySecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to ZeroTier identity.secret file";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      clan.core.vars.generators = {
        ${identityGenerator} = {
          share = true;
          files.identity-secret = { };
          runtimeInputs = [ zerotierTools ];
          script = ''
            zerotier-generate --mode identity-only --identity-secret "$out/identity-secret"
          '';
        };

        ${ipGenerator} = {
          share = true;
          files.ip = {
            secret = false;
            deploy = false;
          };
          runtimeInputs = [ zerotierTools ];
          dependencies = [
            identityGenerator
            networkGenerator
          ];
          script = ''
            zerotier-generate --mode compute-ip \
              --identity-secret "$in/${identityGenerator}/identity-secret" \
              --network-id-file "$in/${networkGenerator}/network-id" \
              --ip "$out/ip"
          '';
        };
      };

      services.zerotierone = {
        enable = true;
        joinNetworks = lib.mkIf (cfg.networkId != null) [ cfg.networkId ];
        identitySecretFile =
          config.clan.core.vars.generators.${identityGenerator}.files.identity-secret.path;
      };
    })

    (lib.mkIf config.services.zerotierone.enable {
      environment.systemPackages = [ pkgs.zerotierone ];

      # Keep .i available while clients migrate to the ZeroTier-specific .z suffix.
      environment.etc."resolver/i" = lib.mkIf (tapsZerotierIP != null) {
        text = "nameserver ${tapsZerotierIP}\n";
      };
      environment.etc."resolver/z" = lib.mkIf (tapsZerotierIP != null) {
        text = "nameserver ${tapsZerotierIP}\n";
      };

      # /etc/hosts entries via clan-core launchd daemon
      clan.core.networking.extraHosts.zerotier = lib.concatStringsSep "\n" [
        (mkHostsEntries zerotierIPs "i")
        (mkHostsEntries zerotierIPs "z")
      ];

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
              launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
              sleep 1

              if [ -f "${ztDataDir}/identity.secret" ]; then
                cp "${ztDataDir}/identity.secret" "${ztDataDir}/identity.secret.bak.$(date +%s)"
                rm -f "${ztDataDir}/identity.public"
              fi
              cp "${config.services.zerotierone.identitySecretFile}" "${ztDataDir}/identity.secret"
              chmod 600 "${ztDataDir}/identity.secret"
              ${ztIdTool} getpublic "${ztDataDir}/identity.secret" > "${ztDataDir}/identity.public"

              echo "Restarting ZeroTier daemon with new identity..."
              launchctl load /Library/LaunchDaemons/com.zerotier.one.plist 2>/dev/null || true
            fi
          fi
        ''}

        # Wait for zerotier daemon to be ready
        for i in {1..15}; do
          if ${ztCli} info >/dev/null 2>&1; then
            break
          fi
          echo "Waiting for ZeroTier daemon... ($i/15)"
          sleep 1
        done

        ${lib.concatMapStringsSep "\n" (network: ''
          # Match the network-id column exactly; a bare grep would also match
          # the id as a substring of another network's row.
          if ! ${ztCli} listnetworks 2>/dev/null | awk '{print $3}' | grep -qx "${network}"; then
            echo "Joining ZeroTier network ${network}..."
            ${ztCli} join "${network}" || true
          fi
        '') config.services.zerotierone.joinNetworks}
      '';
    })
  ];
}
