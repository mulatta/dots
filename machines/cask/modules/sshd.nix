{
  config,
  lib,
  ...
}:
let
  sshPort = toString (lib.head (config.services.openssh.ports or [ 22 ]));
  privateMeshCidrs = [
    "10.208.0.0/12"
    "fdec:ca5f::/32"
    "fd28:387a::/40"
  ];
  privateMeshMatch = lib.concatStringsSep "," privateMeshCidrs;
in
{
  services.openssh.settings = {
    PermitRootLogin = lib.mkDefault "prohibit-password";
    PubkeyAuthentication = true;
    PermitEmptyPasswords = false;

    AllowAgentForwarding = false;
    AllowTcpForwarding = false;
    PermitUserEnvironment = false;
    Compression = false;

    MaxAuthTries = 3;
    MaxSessions = 20;
    LoginGraceTime = 15;
    MaxStartups = "50:30:100";
    PerSourceMaxStartups = 10;
    PerSourcePenaltyExemptList = privateMeshMatch;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;

    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
    ];

    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
  };

  # Allow root login and TCP forwarding from internal networks only
  services.openssh.extraConfig = ''
    # Private mesh networks
    Match Address ${privateMeshMatch}
        PermitRootLogin prohibit-password
        AllowTcpForwarding yes

  '';

  # Fail2ban for VPS protection
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "24h";
    bantime-increment.enable = true;

    ignoreIP = [
      "127.0.0.1/8"
      "::1/128"
    ]
    ++ privateMeshCidrs;

    jails = {
      sshd.settings.enabled = false;

      sshd-aggressive.settings = {
        enabled = true;
        port = sshPort;
        filter = "sshd[mode=aggressive]";
        maxretry = 3;
        findtime = 3600;
        bantime = 86400;
        # Restrict the reader to the system journal so user-journal file
        # descriptors cannot mask a lost system journal after rotation.
        backend = "systemd[journalflags=4]";
      };
    };
  };
}
