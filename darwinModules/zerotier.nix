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

  # Helper to read clan vars
  readVarFile =
    machine: generator: file:
    let
      path = self + "/vars/per-machine/${machine}/${generator}/${file}/value";
    in
    if builtins.pathExists path then lib.strings.trim (builtins.readFile path) else null;

  # ZeroTier IPs for .i domain
  zerotierIPs = {
    taps = readVarFile "taps" "zerotier" "zerotier-ip";
    malt = readVarFile "malt" "zerotier" "zerotier-ip";
    pint = readVarFile "pint" "zerotier" "zerotier-ip";
    rhesus = readVarFile "rhesus" "zerotier" "zerotier-ip";
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

    controller.machineName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name of the machine that acts as ZeroTier controller";
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
      # Vars generator for zerotier identity
      clan.core.vars.generators.zerotier = {
        files.zerotier-identity-secret = {
          secret = true;
        };
        files.zerotier-ip = { };
        script = ''
          ${pkgs.zerotierone}/bin/zerotier-idtool generate "$out/zerotier-identity-secret"
          IDENTITY_PUBLIC=$(${pkgs.zerotierone}/bin/zerotier-idtool getpublic "$out/zerotier-identity-secret")
          NODE_ID=$(echo "$IDENTITY_PUBLIC" | cut -d: -f1)
          NETWORK_ID="${toString cfg.networkId}"
          if [ -n "$NETWORK_ID" ]; then
            PREFIX="fd''${NETWORK_ID:0:2}:''${NETWORK_ID:2:4}:''${NETWORK_ID:6:4}:''${NETWORK_ID:10:4}"
            SUFFIX="''${NODE_ID:0:2}''${NODE_ID:2:2}:''${NODE_ID:4:4}:''${NODE_ID:6:2}''${NODE_ID:8:2}"
            echo "$PREFIX:$SUFFIX" > "$out/zerotier-ip"
          fi
        '';
      };

      # Link clan options to service options
      services.zerotierone = {
        enable = true;
        joinNetworks = lib.mkIf (cfg.networkId != null) [ cfg.networkId ];
        identitySecretFile = config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
      };
    })

    (lib.mkIf config.services.zerotierone.enable {
      environment.systemPackages = [ pkgs.zerotierone ];

      # DNS resolver for .i domain → taps ZeroTier IP
      environment.etc."resolver/i" = lib.mkIf (tapsZerotierIP != null) {
        text = "nameserver ${tapsZerotierIP}\n";
      };

      # /etc/hosts entries via clan-core launchd daemon
      clan.core.networking.extraHosts.zerotier = mkHostsEntries zerotierIPs "i";

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
          if ! ${ztCli} listnetworks 2>/dev/null | grep -q "${network}"; then
            echo "Joining ZeroTier network ${network}..."
            ${ztCli} join "${network}" || true
          fi
        '') config.services.zerotierone.joinNetworks}
      '';
    })
  ];
}
