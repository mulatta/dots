{
  config,
  maltNeko,
  pkgs,
  ...
}:
let
  inherit (maltNeko)
    image
    network
    paths
    ports
    wireguardAddress
    ;

  chromiumConfig = pkgs.writeText "neko-chromium.conf" ''
    [program:chromium]
    environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"
    command=/usr/bin/chromium
      --no-sandbox
      --window-position=0,0
      --display=%(ENV_DISPLAY)s
      --user-data-dir=/home/neko/chrome-profile
      --no-first-run
      --start-maximized
      --force-dark-mode
      --disable-file-system
      --disable-gpu
      --disable-software-rasterizer
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
      DeveloperToolsAvailability = 2;
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
        NEKO_WEBRTC_NAT1TO1 = wireguardAddress;
        NEKO_WEBRTC_TCPMUX = toString ports.media;
        NEKO_WEBRTC_UDPMUX = toString ports.media;
        TZ = "Asia/Seoul";
      };
      ports = [
        "[${wireguardAddress}]:${toString ports.ui.host}:${toString ports.ui.container}/tcp"
        "[${wireguardAddress}]:${toString ports.media}:${toString ports.media}/tcp"
        "[${wireguardAddress}]:${toString ports.media}:${toString ports.media}/udp"
      ];
      volumes = [
        "${paths.profile}:/home/neko/chrome-profile:rw"
        "${chromiumConfig}:/etc/neko/supervisord/chromium.conf:ro"
        "${chromiumPolicy}:/etc/chromium/policies/managed/policies.json:ro"
      ];
      extraOptions = [
        "--dns=1.1.1.1"
        "--dns=8.8.8.8"
        "--pids-limit=512"
        "--security-opt=no-new-privileges"
        "--shm-size=2g"
      ];
    };
  };

  systemd.services.podman-neko.restartTriggers = [
    chromiumConfig
    chromiumPolicy
    image
  ];
}
