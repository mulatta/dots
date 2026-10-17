# Host side of the Hermes container built from the private hermes flake.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  vars = config.clan.core.vars.generators;
  noa = config.services.buzz-agents.agents.noa;
  cask = self.nixosConfigurations.cask.config.networking.naru;

  # Must match the hermes flake's system.build.hostContract.
  stateDir = "/var/lib/hermes";
  uid = 2001;
  dashboardPort = 9119;
  hostAddress = "10.90.0.1";
  credentials = {
    noa-slack-bot-token = vars.hermes.files.slack-bot-token.path;
    noa-slack-app-token = vars.hermes.files.slack-app-token.path;
    noa-discord-bot-token = vars.hermes-discord.files.bot-token.path;
    noa-sparkyfitness-api-key = vars.hermes-sparkyfitness.files.api-key.path;
    noa-buzz-private-key = noa.privateKeyFile;
    noa-buzz-auth-tag = noa.authTagFile;
    noa-agentgateway-token = vars.agentgateway-client-hermes.files.token.path;
    hindsight-api-key = vars.hindsight.files.api-key.path;
  };
  localAddress = "10.90.0.2";
  iface = "ve-hermes";
  relayPort = 9120;
  loopbackServices = {
    hindsight-api = 8890;
    searxng = 8888;
    neko-cdp = 9222;
  };
  secret = description: {
    inherit description;
    type = "hidden";
    persist = true;
  };
in
{
  clan.core.vars.generators = {
    hermes.prompts = {
      slack-bot-token = secret "Slack bot token (xoxb-…) for the noa app";
      slack-app-token = secret "Slack app-level token (xapp-…) with connections:write for noa";
    };
    hermes-discord.prompts.bot-token = secret "Discord bot token for Hermes";
    hermes-sparkyfitness.prompts.api-key = secret "SparkyFitness ordinary-user API key for Hermes MCP";
    # Add deploy-key.pub to mulatta/hermes as a read-only deploy key.
    hermes-flake-ssh = {
      files.deploy-key.secret = true;
      files."deploy-key.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C hermes-flake-ssh@malt -f "$out/deploy-key"
      '';
    };
  };

  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    inherit uid;
    home = stateDir;
  };
  users.groups.hermes.gid = uid;
  systemd.tmpfiles.rules = [ "d ${stateDir} 0750 hermes hermes -" ];

  # Update without a host rebuild: `nixos-container update hermes`.
  containers.hermes = {
    flake = "git+ssh://gitea@cask.n/mulatta/hermes#hermes";
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;
    bindMounts.${stateDir} = {
      hostPath = stateDir;
      isReadOnly = false;
    };
    extraFlags = lib.mapAttrsToList (name: file: "--load-credential=${name}:${file}") credentials;
  };

  programs.ssh.extraConfig = ''
    Match host cask.n user gitea
      IdentityFile ${vars.hermes-flake-ssh.files.deploy-key.path}
      IdentitiesOnly yes
  '';

  services.buzz-agents = {
    relayUrl = "https://buzz.mulatta.io";
    ownerPubkey = self.nixosConfigurations.cask.config.services.buzz-relay.ownerPubkey;
    agents.noa = {
      displayName = "noa";
      avatar = "https://buzz.mulatta.io/media/ead748a855e4c6d64175becc7ac611dfcace4ab5b09bb8e58028d38721e93343.png";
      # Also hardcoded in the hermes flake's profiles/noa.
      channels = [ "6fd9e6ce-242e-51ce-b931-7644668b87de" ];
      before = [ "container@hermes.service" ];
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ iface ];
    externalInterface = "enp1s0";
  };
  networking.firewall.interfaces.${iface} = {
    allowedTCPPorts = [
      config.services.agentgateway.settings.gateways.default.port
      53
    ]
    ++ lib.attrValues loopbackServices;
    allowedUDPPorts = [ 53 ];
  };
  services.resolved.settings.Resolve.DNSStubListenerExtra = hostAddress;
  # The NixOS firewall does not filter forwarded traffic.
  networking.nftables.tables.hermes-isolation = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -5; policy accept;
        iifname "${iface}" ct state established,related accept
        iifname "${iface}" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } drop
        iifname "${iface}" ip6 daddr { ::1/128, fc00::/7, fe80::/10 } drop
      }
    '';
  };
  systemd.sockets = lib.mapAttrs' (
    name: port:
    lib.nameValuePair "hermes-proxy-${name}" {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${hostAddress}:${toString port}" ];
      socketConfig.FreeBind = true;
    }
  ) loopbackServices;
  systemd.services = lib.mapAttrs' (
    name: port:
    lib.nameValuePair "hermes-proxy-${name}" {
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString port}";
        DynamicUser = true;
        PrivateTmp = true;
      };
    }
  ) loopbackServices;

  # FODs run in the host namespace and would bypass the container's isolation.
  nix.firewall = {
    enable = true;
    allowPrivateNetworks = false;
    extraNftablesRules = [
      # resolved.nix only opens UDP.
      "ip daddr { 127.0.0.53, 127.0.0.54 } tcp dport 53 accept"
      # Missing from nixpkgs' private ranges.
      "ip daddr 100.64.0.0/10 counter drop"
      "ip6 daddr fc00::/7 counter drop"
    ];
  };
  networking.nftables.flushRuleset = false;

  services.nginx.enable = true;
  services.nginx.virtualHosts."hermes.mulatta.io" = {
    listen =
      map
        (addr: {
          inherit addr;
          port = relayPort;
        })
        (
          with config.networking.naru;
          [
            ipv4
            "[${ipv6}]"
          ]
        );
    extraConfig = ''
      allow ${cask.ipv4};
      allow ${cask.ipv6};
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://${localAddress}:${toString dashboardPort}";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      # Hermes needs https for Secure session cookies.
      extraConfig = ''
        proxy_set_header Host hermes.mulatta.io;
        proxy_set_header X-Forwarded-Host hermes.mulatta.io;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ relayPort ];
}
