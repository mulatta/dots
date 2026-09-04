{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  ports = {
    ui = {
      host = 8082;
      container = 8080;
    };
    media = 59000;
    cdp = {
      host = 9222;
      chromium = 9222;
      relay = 9223;
    };
  };

  state = "/var/lib/neko";
  profile = "/var/lib/neko/chrome-profile";

  network = {
    name = "neko";
    interface = "neko0";
    id = "6e656b6f00000000000000000000000000000000000000000000000000000000";
    ipv4 = {
      subnet = "10.89.0.0/24";
      gateway = "10.89.0.1";
    };
    ipv6 = {
      subnet = "fd89:6e65:6b6f::/64";
      gateway = "fd89:6e65:6b6f::1";
    };
  };

  image = self.packages.${pkgs.stdenv.hostPlatform.system}.neko-image;

  podmanNetworkConfig = (pkgs.formats.json { }).generate "neko-podman-network.json" {
    name = network.name;
    inherit (network) id;
    driver = "bridge";
    network_interface = network.interface;
    created = "2026-08-10T00:00:00Z";
    subnets = [
      network.ipv4
      network.ipv6
    ];
    ipv6_enabled = true;
    internal = false;
    dns_enabled = false;
    ipam_options.driver = "host-local";
    options.isolate = "true";
  };

  clearStaleChromiumProcessLocks = pkgs.writeShellScript "neko-clear-stale-chromium-process-locks" ''
    # The previous container is gone, so persistent locks can only refer to dead runtime state.
    rm -f \
      ${profile}/SingletonCookie \
      ${profile}/SingletonLock \
      ${profile}/SingletonSocket
  '';

  chromiumConfig = pkgs.writeText "neko-chromium.conf" ''
    [program:chromium]
    environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"
    command=/usr/bin/chromium
      --no-sandbox
      --window-position=0,0
      --display=%(ENV_DISPLAY)s
      --user-data-dir=/home/neko/chrome-profile
      --remote-debugging-address=127.0.0.1
      --remote-debugging-port=${toString ports.cdp.chromium}
      --no-first-run
      --start-maximized
      --force-dark-mode
      --disable-file-system
      --disable-dev-shm-usage
    stopsignal=INT
    autorestart=true
    priority=800
    user=%(ENV_USER)s
    stdout_logfile=/var/log/neko/chromium.log
    stdout_logfile_maxbytes=100MB
    stdout_logfile_backups=10
    redirect_stderr=true

    [program:openbox]
    environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"
    command=/usr/bin/openbox --config-file /etc/neko/openbox.xml
    autorestart=true
    priority=300
    user=%(ENV_USER)s
    stdout_logfile=/var/log/neko/openbox.log
    stdout_logfile_maxbytes=100MB
    stdout_logfile_backups=10
    redirect_stderr=true

    # Chromium ignores remote-debugging-address in this image. Keep it on
    # loopback and expose full native CDP through a transport-only relay.
    [program:cdp-relay]
    command=/usr/local/bin/socat TCP-LISTEN:${toString ports.cdp.relay},fork,reuseaddr TCP:127.0.0.1:${toString ports.cdp.chromium}
    autorestart=true
    priority=900
    user=%(ENV_USER)s
    stdout_logfile=/var/log/neko/cdp-relay.log
    stdout_logfile_maxbytes=10MB
    stdout_logfile_backups=2
    redirect_stderr=true
  '';

  chromiumPolicy = pkgs.writeText "neko-chromium-policy.json" (
    builtins.toJSON {
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      AutoplayAllowed = true;
      BrowserAddPersonEnabled = false;
      BrowserGuestModeEnabled = false;
      BrowserLabsEnabled = false;
      BrowserSignin = 0;
      CommandLineFlagSecurityWarningsEnabled = false;
      DefaultCookiesSetting = 1;
      DefaultNotificationsSetting = 2;
      DefaultPopupsSetting = 2;
      DeveloperToolsAvailability = 1;
      DownloadRestrictions = 3;
      EditBookmarksEnabled = false;
      ExtensionInstallBlocklist = [ "*" ];
      FullscreenAllowed = true;
      IncognitoModeAvailability = 1;
      PasswordManagerEnabled = false;
      PromptForDownloadLocation = false;
      RestoreOnStartup = 1;
      SyncDisabled = true;
      VideoCaptureAllowed = true;
    }
  );

  secretEnv = config.clan.core.vars.generators.neko.files.env.path;
in
{
  clan.core.vars.generators.neko = {
    files = {
      env.secret = true;
      user-password = {
        secret = true;
        deploy = false;
      };
      admin-password = {
        secret = true;
        deploy = false;
      };
    };
    files.env.restartUnits = [ "podman-neko.service" ];
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      set -euo pipefail

      openssl rand -hex 24 > "$out/user-password"
      openssl rand -hex 24 > "$out/admin-password"
      {
        printf 'NEKO_MEMBER_MULTIUSER_USER_PASSWORD=%s\n' "$(cat "$out/user-password")"
        printf 'NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD=%s\n' "$(cat "$out/admin-password")"
      } > "$out/env"
    '';
  };

  # Browser credentials stay local; offsite backup sources exclude this path.
  systemd.tmpfiles.rules = [
    "d ${state} 0700 1000 1000 -"
    "d ${profile} 0700 1000 1000 -"
  ];

  environment.etc."containers/networks/${network.name}.json".source = podmanNetworkConfig;

  networking.firewall.interfaces."tinc.naru" = {
    allowedTCPPorts = [
      ports.ui.host
      ports.media
    ];
    allowedUDPPorts = [ ports.media ];
  };

  networking.firewall.extraForwardRules = ''
    iifname "tinc.naru" oifname "${network.interface}" tcp dport { ${toString ports.ui.container}, ${toString ports.media} } accept
    iifname "tinc.naru" oifname "${network.interface}" udp dport ${toString ports.media} accept
    iifname "${network.interface}" oifname "tinc.naru" ct state established,related accept
  '';

  # Keep the browser away from malt and overlay-network services if a visited
  # page compromises Chromium. Internet egress remains available.
  networking.nftables.tables.neko-isolation = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -5; policy accept;
        iifname "${network.interface}" icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert } accept
        iifname "${network.interface}" ct state established,related accept
        iifname "${network.interface}" drop
      }

      chain forward {
        type filter hook forward priority -5; policy accept;
        iifname "${network.interface}" ct state established,related accept
        iifname "${network.interface}" ip daddr {
          10.0.0.0/8,
          100.64.0.0/10,
          127.0.0.0/8,
          169.254.0.0/16,
          172.16.0.0/12,
          192.168.0.0/16
        } drop
        iifname "${network.interface}" ip6 daddr { ::1/128, fc00::/7, fe80::/10 } drop
      }
    '';
  };

  systemd.services.podman-neko = {
    after = [ "systemd-tmpfiles-setup.service" ];
    # OCI pre-start removes the old container before persistent process locks are cleared.
    serviceConfig.ExecStartPre = lib.mkAfter [ clearStaleChromiumProcessLocks ];
    restartTriggers = [
      podmanNetworkConfig
      chromiumConfig
      chromiumPolicy
      image
      pkgs.pkgsStatic.socat
    ];
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.neko = {
      image = "${image.imageName}:${image.imageTag}";
      imageFile = image;
      pull = "never";
      hostname = "neko";
      networks = [ network.name ];
      environmentFiles = [ secretEnv ];
      environment = {
        NEKO_DESKTOP_SCREEN = "1920x1080@30";
        NEKO_MEMBER_PROVIDER = "multiuser";
        NEKO_SESSION_COOKIE_SECURE = "false";
        NEKO_WEBRTC_ICELITE = "true";
        NEKO_WEBRTC_NAT1TO1 = config.networking.naru.ipv6;
        NEKO_WEBRTC_TCPMUX = toString ports.media;
        NEKO_WEBRTC_UDPMUX = toString ports.media;
        TZ = "Asia/Seoul";
      };
      ports = [
        "[::]:${toString ports.ui.host}:${toString ports.ui.container}/tcp"
        "[::]:${toString ports.media}:${toString ports.media}/tcp"
        "[::]:${toString ports.media}:${toString ports.media}/udp"
        "127.0.0.1:${toString ports.cdp.host}:${toString ports.cdp.relay}/tcp"
      ];
      volumes = [
        "${profile}:/home/neko/chrome-profile:rw"
        "${chromiumConfig}:/etc/neko/supervisord/chromium.conf:ro"
        "${chromiumPolicy}:/etc/chromium/policies/managed/policies.json:ro"
        "${pkgs.pkgsStatic.socat}/bin/socat:/usr/local/bin/socat:ro"
      ];
      extraOptions = [
        "--device=/dev/dri/renderD128:/dev/dri/renderD128"
        "--dns=1.1.1.1"
        "--dns=8.8.8.8"
        "--pids-limit=512"
        "--security-opt=no-new-privileges"
        "--shm-size=2g"
      ];
    };
  };

}
