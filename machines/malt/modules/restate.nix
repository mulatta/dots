{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  tapsWgIP = "${wgPrefix}::1";
  requestIdentity = config.clan.core.vars.generators.restate-request-identity;
in
{
  imports = [
    self.inputs.restate-workflows.nixosModules.url-media-archive
  ];

  disko.devices.zpool.zroot.datasets."restate" = {
    type = "zfs_fs";
    mountpoint = "/var/lib/restate";
    options = {
      compression = "lz4";
      "com.sun:auto-snapshot" = "true";
    };
  };

  clan.core.vars.generators.restate-request-identity = {
    files."private-key.pem" = {
      secret = true;
      owner = "restate";
      group = "restate";
    };
    files."public-key".secret = false;

    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.python3
    ];

    script = ''
      private_key="$out/private-key.pem"
      public_der="$out/public-key.der"

      openssl genpkey -algorithm ed25519 -out "$private_key"
      openssl pkey -in "$private_key" -pubout -outform DER -out "$public_der"

      python3 - "$public_der" > "$out/public-key" <<'PY'
      import sys

      alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
      data = open(sys.argv[1], "rb").read()[-32:]
      number = int.from_bytes(data, "big")
      encoded = ""
      while number > 0:
          number, remainder = divmod(number, 58)
          encoded = alphabet[remainder] + encoded
      encoded = (alphabet[0] * (len(data) - len(data.lstrip(b"\\0")))) + encoded
      print("publickeyv1_" + encoded, end="")
      PY

      rm "$public_der"
    '';
  };

  services.restate = {
    enable = true;
    ingressBindAddress = "[${maltWgIP}]:8081";
    adminBindAddress = "[${maltWgIP}]:9070";
    settings = {
      cluster-name = "opencrow";
      disable-telemetry = true;
      request-identity-private-key-pem-file = requestIdentity.files."private-key.pem".path;
    };
  };

  services.restateWorkers.url-media-archive = {
    enable = true;
    package =
      self.inputs.restate-workflows.packages.${pkgs.stdenv.hostPlatform.system}.url-media-archive;
    group = "media";
    restateAdminUrl = "http://[${maltWgIP}]:9070";
    endpointUrl = "http://127.0.0.1:9080";
    archiveRoot = "/srv/media/videos/url-media-archive/A";
    cookiePath = "/var/lib/url-media-archive/cookies/browser.netscape.txt";
    ytDlpProbeConcurrency = 1;
    ytDlpDownloadConcurrency = 1;
    ytDlpRequestMinIntervalMs = 10000;
    ytDlpRequestJitterMs = 10000;
    requestIdentity.publicKeys = [
      requestIdentity.files."public-key".value
    ];
  };

  systemd.services.restate = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.services.url-media-archive-worker.unitConfig.RequiresMountsFor = [
    "/srv/media"
  ];

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [
    8081 # HTTP ingress
  ];

  networking.firewall.extraInputRules = ''
    iifname "wireguard" ip6 saddr ${tapsWgIP} tcp dport 9070 accept comment "Allow Restate Admin only from taps proxy"
  '';
}
