{
  self,
  config,
  pkgs,
  ...
}:
let
  requestIdentity = config.clan.core.vars.generators.restate-request-identity;
in
{
  imports = [
    self.inputs.automation-runtime.nixosModules.url-media-archive
  ];

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
    ingressBindAddress = "[::]:8081";
    adminBindAddress = "[::]:9070";
    settings = {
      cluster-name = "opencrow";
      disable-telemetry = true;
      request-identity-private-key-pem-file = requestIdentity.files."private-key.pem".path;
    };
  };

  services.restateWorkers.url-media-archive = {
    enable = true;
    package =
      self.inputs.automation-runtime.packages.${pkgs.stdenv.hostPlatform.system}.url-media-archive;
    group = "media";
    restateAdminUrl = "http://[::1]:9070";
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

  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [
    8081 # HTTP ingress
    9070 # Admin API
  ];
}
