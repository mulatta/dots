{ pkgs, ... }:
let
  agentBridge = "br-agents";
  hostAddress = "10.233.0.1";
  localAddress = "10.233.0.10";
in
{
  networking = {
    bridges.${agentBridge}.interfaces = [ ];
    interfaces.${agentBridge}.ipv4.addresses = [
      {
        address = hostAddress;
        prefixLength = 24;
      }
    ];

    nat = {
      enable = true;
      externalInterface = "enp1s0";
      internalInterfaces = [ agentBridge ];
    };

    firewall.filterForward = true;
    nftables.tables.hermes-isolation = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -5; policy accept;
          iifname "${agentBridge}" ct state established,related accept
          iifname "${agentBridge}" drop
        }

        chain forward {
          type filter hook forward priority -5; policy accept;
          iifname "${agentBridge}" ct state established,related accept
          iifname "${agentBridge}" oifname "enp1s0" tcp dport 443 accept
          iifname "${agentBridge}" oifname "enp1s0" udp dport 53 accept
          iifname "${agentBridge}" oifname "enp1s0" tcp dport 53 accept
          iifname "${agentBridge}" drop
        }
      '';
    };
  };

  containers.hermes = {
    privateNetwork = true;
    hostBridge = agentBridge;
    localAddress = "${localAddress}/24";

    config = _: {
      networking = {
        useHostResolvConf = false;
        nftables.enable = true;
        defaultGateway = {
          address = hostAddress;
          interface = "eth0";
        };
        nameservers = [
          "117.16.191.6"
          "168.126.63.1"
        ];
        firewall.extraInputRules = ''
          ip saddr ${hostAddress} tcp dport 9119 accept
        '';
      };

      systemd.sockets.hermes-dashboard-proxy = {
        description = "Private bridge socket for the Hermes dashboard";
        wantedBy = [ "sockets.target" ];
        socketConfig.ListenStream = "${localAddress}:9119";
      };

      systemd.services.hermes-dashboard-proxy = {
        description = "Proxy the private bridge to the loopback-only Hermes dashboard";
        after = [ "hermes-dashboard.service" ];
        requires = [ "hermes-dashboard.service" ];
        serviceConfig = {
          User = "hermes";
          Group = "hermes";
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:9119";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };
    };
  };
}
