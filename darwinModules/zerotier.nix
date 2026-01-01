{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.services.zerotierone = {
    enable = lib.mkEnableOption "ZeroTier One";

    joinNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of ZeroTier network IDs to join on startup";
    };
  };

  config = lib.mkIf config.services.zerotierone.enable {
    environment.systemPackages = [ pkgs.zerotierone ];

    launchd.daemons.zerotierone = {
      serviceConfig = {
        Label = "com.zerotier.one";
        ProgramArguments = [ "${pkgs.zerotierone}/bin/zerotier-one" ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    # Join networks on activation using zerotier-cli
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Setting up ZeroTier..."
      # Wait for zerotier daemon to be ready (up to 5 seconds)
      for _ in 1 2 3 4 5; do
        if ${pkgs.zerotierone}/bin/zerotier-cli info >/dev/null 2>&1; then
          break
        fi
        echo "Waiting for ZeroTier daemon..."
        sleep 1
      done

      ${lib.concatMapStringsSep "\n" (network: ''
        if ! ${pkgs.zerotierone}/bin/zerotier-cli listnetworks 2>/dev/null | grep -q "${network}"; then
          echo "Joining ZeroTier network ${network}..."
          ${pkgs.zerotierone}/bin/zerotier-cli join "${network}" || true
        fi
      '') config.services.zerotierone.joinNetworks}
    '';
  };
}
