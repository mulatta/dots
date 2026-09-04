# Web frontend for radicle-mirror: explorer, API, and search index.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  meiliUrl = "http://127.0.0.1:${toString config.services.meilisearch.listenPort}";
  mirrorStateDirectory = "/var/lib/radicle-mirror";
  radicle-httpd = pkgs.radicle-httpd.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./radicle-search-debounce.patch
      ./radicle-httpd-zstd-archive.patch
      ./radicle-httpd-archive-404.patch
    ];
    nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.zstd ];
    postFixup = (old.postFixup or "") + ''
      for program in $out/bin/*; do
        wrapProgram "$program" --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.zstd ]}
      done
    '';
  });
  sharedServiceConfig = {
    Restart = "on-failure";
    RestartSec = 5;
    DynamicUser = true;
    User = "radicle-mirror";
    StateDirectory = "radicle-mirror";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    MemoryHigh = "512M";
    MemoryMax = "768M";
  };
in
{
  services.meilisearch = {
    enable = true;
    listenAddress = "127.0.0.1";
  };
  systemd.services.meilisearch.serviceConfig = {
    MemoryHigh = "1G";
    MemoryMax = "1536M";
  };

  systemd.services.radicle-search = {
    description = "Radicle mirror search indexer";
    wantedBy = [ "multi-user.target" ];
    after = [
      "radicle-mirror.service"
      "meilisearch.service"
    ];
    wants = [ "meilisearch.service" ];
    serviceConfig = sharedServiceConfig // {
      ExecStart = "${radicle-httpd}/bin/radicle-search";
      Environment = [
        "RAD_HOME=${mirrorStateDirectory}/rad"
        "RADICLE_SEARCH_MEILI_URL=${meiliUrl}"
      ];
    };
  };

  systemd.services.radicle-httpd = {
    description = "Radicle mirror HTTP gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "radicle-mirror.service" ];
    serviceConfig = sharedServiceConfig // {
      ExecStart = "${radicle-httpd}/bin/radicle-httpd --listen 127.0.0.1:8889";
      Environment = [
        "RAD_HOME=${mirrorStateDirectory}/rad"
        "RADICLE_SEARCH_URL=${meiliUrl}"
      ];
    };
  };
  services.nginx.virtualHosts."rad.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    root = lib.mkForce "${pkgs.radicle-explorer.withConfig {
      preferredSeeds = [
        {
          hostname = "rad.mulatta.io";
          port = 443;
          scheme = "https";
        }
      ];
    }}";

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
      extraConfig = ''
        add_header Cache-Control "public, max-age=3600";
      '';
    };

    locations."/api/" = {
      proxyPass = "http://127.0.0.1:8889";
      proxyWebsockets = true;
    };
  };
}
