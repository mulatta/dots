{
  config,
  lib,
  ...
}:
let
  sshPort = toString (lib.head (config.services.openssh.ports or [ 22 ]));
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
    MaxSessions = 5;
    LoginGraceTime = 30;
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
    # WireGuard mesh network
    Match Address fdec:ca5f::/32
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
      "fdec:ca5f::/32"
    ];

    jails = {
      sshd = {
        settings = {
          enabled = true;
          port = sshPort;
          filter = "sshd";
          maxretry = 3;
          findtime = 600;
          bantime = 86400;
          backend = "systemd";
        };
      };

      sshd-aggressive = {
        settings = {
          enabled = true;
          port = sshPort;
          filter = "sshd[mode=aggressive]";
          maxretry = 3;
          findtime = 3600;
          bantime = 86400;
          backend = "systemd";
        };
      };
    };
  };
}
