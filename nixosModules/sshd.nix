{ lib, ... }:
{
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      PermitEmptyPasswords = false;
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

      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
      ];

      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "24h";
    bantime-increment.enable = true;
    ignoreIP = [
      "127.0.0.1/8"
      "::1/128"
      "10.0.0.0/8"
    ];

    jails = {
      sshd = {
        settings = {
          enabled = true;
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
          filter = "sshd[mode=aggressive]";
          maxretry = 1;
          findtime = 86400;
          bantime = 604800;
          backend = "systemd";
        };
      };
    };
  };
}
